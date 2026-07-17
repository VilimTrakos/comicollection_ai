from __future__ import annotations

import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_schema import (
    MAX_ACTIVE_SESSIONS_PER_ACCOUNT,
    SUPPORTED_AUTH_SCHEMA_VERSION,
)
from comicollect_backend.auth_service import AuthService
from comicollect_backend.rate_limit import RateLimiter, RatePolicy

from tests.support import (
    PASSWORD,
    MutableClock,
    account_from,
    error_code,
    make_auth_service,
    make_hasher,
    mapping,
    registration,
    token_from,
)


class AuthServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.clock = MutableClock()
        self.service = make_auth_service(
            Path(self.temporary.name) / "auth.sqlite3",
            clock=self.clock,
        )

    def test_register_normalizes_email_and_duplicate_does_not_replace_account(self) -> None:
        created = registration(self.service, "  Reader@Example.COM  ")
        self.assertEqual(account_from(created)["email"], "reader@example.com")

        with error_code(self, "email_in_use"):
            registration(self.service, "reader@example.com")

        logged_in = self.service.login(
            email="READER@example.com",
            password=PASSWORD,
            installation_id="second-installation",
        )
        self.assertEqual(account_from(logged_in)["id"], account_from(created)["id"])

    def test_registration_can_be_disabled_without_disabling_login(self) -> None:
        database = Path(self.temporary.name) / "closed-registration.sqlite3"
        enabled = make_auth_service(database, clock=self.clock)
        registration(enabled)
        disabled = make_auth_service(
            database,
            clock=self.clock,
            registration_enabled=False,
        )
        with error_code(self, "registration_disabled"):
            registration(disabled, "other@example.com")
        logged_in = disabled.login(
            email="reader@example.com",
            password=PASSWORD,
            installation_id="installation-b",
        )
        self.assertEqual(account_from(logged_in)["email"], "reader@example.com")

    def test_registration_is_disabled_by_default(self) -> None:
        service = AuthService(
            AuthRepository(Path(self.temporary.name) / "default-closed.sqlite3"),
            make_hasher(),
            token_key=b"p" * 32,
            clock=self.clock,
            access_ttl_ms=60_000,
            refresh_ttl_ms=600_000,
            session_ttl_ms=3_600_000,
        )

        with error_code(self, "registration_disabled"):
            registration(service)

    def test_restart_fails_closed_when_token_key_changes(self) -> None:
        database = Path(self.temporary.name) / "key-pinning.sqlite3"
        make_auth_service(database, clock=self.clock)

        with self.assertRaisesRegex(ValueError, "token key"):
            AuthService(
                AuthRepository(database),
                make_hasher(pepper=b"different-secret-material-32-bytes!"),
                token_key=b"different-secret-material-32-bytes!",
                clock=self.clock,
            )

    def test_repeated_login_attempts_are_rate_limited(self) -> None:
        registration(self.service)
        self.service.rate_limiter = RateLimiter(
            clock=self.clock,
            limit=2,
            window_ms=60_000,
        )
        for _ in range(2):
            with error_code(self, "invalid_credentials"):
                self.service.login(
                    email="reader@example.com",
                    password="wrong password that is long enough",
                    installation_id="installation-b",
                    rate_key="203.0.113.9",
                )
        with error_code(self, "rate_limited"):
            self.service.login(
                email="reader@example.com",
                password="wrong password that is long enough",
                installation_id="installation-b",
                rate_key="203.0.113.9",
            )

    def test_wrong_password_and_unknown_account_have_same_public_failure(self) -> None:
        registration(self.service)
        failures = []
        for email, password in (
            ("reader@example.com", "wrong password that is long enough"),
            ("missing@example.com", PASSWORD),
        ):
            try:
                self.service.login(
                    email=email,
                    password=password,
                    installation_id="installation-b",
                )
            except Exception as error:
                failures.append((getattr(error, "code", None), str(error)))
            else:
                self.fail("invalid credentials unexpectedly logged in")
        self.assertEqual(failures[0], failures[1])
        self.assertEqual(failures[0][0], "invalid_credentials")

    def test_access_token_expires_but_refresh_token_can_rotate(self) -> None:
        tokens = registration(self.service)
        access = token_from(tokens, "access_token")
        refresh = token_from(tokens, "refresh_token")
        account_id = account_from(tokens)["id"]
        self.assertEqual(self.service.authenticate_access(access).account_id, account_id)

        self.clock.advance(60_001)
        with error_code(self, "access_expired"):
            self.service.authenticate_access(access)
        rotated = self.service.refresh(
            refresh_token=refresh,
            installation_id="installation-a",
            request_id="refresh-after-access-expiry",
        )
        self.assertNotEqual(token_from(rotated, "access_token"), access)

    def test_refresh_retry_is_idempotent_but_different_id_revokes_family(self) -> None:
        original = registration(self.service)
        old_refresh = token_from(original, "refresh_token")
        arguments = {
            "refresh_token": old_refresh,
            "installation_id": "installation-a",
            "request_id": "refresh-request-1",
        }
        first = mapping(self.service.refresh(**arguments))
        retry = mapping(self.service.refresh(**arguments))
        self.assertEqual(retry, first)
        self.assertEqual(
            self.service.authenticate_access(
                token_from(first, "access_token")
            ).account_id,
            account_from(original)["id"],
        )

        with error_code(self, "refresh_reused"):
            self.service.refresh(
                refresh_token=old_refresh,
                installation_id="installation-a",
                request_id="refresh-request-2",
            )
        with error_code(self, "invalid_token"):
            self.service.authenticate_access(token_from(first, "access_token"))
        with error_code(self, "refresh_expired"):
            self.service.refresh(
                refresh_token=token_from(first, "refresh_token"),
                installation_id="installation-a",
                request_id="refresh-after-family-revocation",
            )

    def test_refresh_is_bound_to_the_session_installation(self) -> None:
        original = registration(self.service, installation_id="installation-a")

        with error_code(self, "invalid_refresh_token"):
            self.service.refresh(
                refresh_token=token_from(original, "refresh_token"),
                installation_id="installation-b",
                request_id="wrong-installation",
            )

        rotated = self.service.refresh(
            refresh_token=token_from(original, "refresh_token"),
            installation_id="installation-a",
            request_id="correct-installation",
        )
        self.assertEqual(account_from(rotated)["id"], account_from(original)["id"])

    def test_opaque_ids_are_bounded_ascii_values(self) -> None:
        with error_code(self, "invalid_request"):
            self.service.register(
                email="unicode-device@example.com",
                password=PASSWORD,
                display_name="Reader",
                installation_id="uređaj-123",
            )

        original = registration(self.service)
        with error_code(self, "invalid_request"):
            self.service.refresh(
                refresh_token=token_from(original, "refresh_token"),
                installation_id="installation-a",
                request_id="kratko",
            )

    def test_refresh_retry_survives_service_restart(self) -> None:
        original = registration(self.service)
        arguments = {
            "refresh_token": token_from(original, "refresh_token"),
            "installation_id": "installation-a",
            "request_id": "crash-recovery-request",
        }
        first = mapping(self.service.refresh(**arguments))

        restarted = make_auth_service(
            self.service.repository.path,
            clock=self.clock,
        )
        retry = mapping(restarted.refresh(**arguments))

        self.assertEqual(retry, first)
        self.assertEqual(
            restarted.authenticate_access(
                token_from(retry, "access_token")
            ).account_id,
            account_from(original)["id"],
        )

    def test_concurrent_refresh_with_same_request_id_returns_same_pair(self) -> None:
        original = registration(self.service)
        refresh = token_from(original, "refresh_token")

        def rotate() -> tuple[str, object]:
            try:
                return (
                    "success",
                    self.service.refresh(
                        refresh_token=refresh,
                        installation_id="installation-a",
                        request_id="concurrent-refresh-request",
                    ),
                )
            except Exception as error:
                return ("error", getattr(error, "code", None))

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(lambda _: rotate(), range(2)))

        successes = [mapping(value) for state, value in outcomes if state == "success"]
        self.assertEqual(len(successes), 2, outcomes)
        self.assertEqual(successes[0], successes[1])
        self.assertEqual(
            self.service.authenticate_access(
                token_from(successes[0], "access_token")
            ).account_id,
            account_from(original)["id"],
        )
        with closing(sqlite3.connect(self.service.repository.path)) as database:
            self.assertEqual(
                database.execute("SELECT COUNT(*) FROM auth_refresh_tokens").fetchone()[0],
                2,
            )

    def test_concurrent_refresh_with_different_ids_revokes_the_session(self) -> None:
        original = registration(self.service)
        refresh = token_from(original, "refresh_token")

        def rotate(request_id: str) -> tuple[str, object]:
            try:
                return (
                    "success",
                    self.service.refresh(
                        refresh_token=refresh,
                        installation_id="installation-a",
                        request_id=request_id,
                    ),
                )
            except Exception as error:
                return ("error", getattr(error, "code", None))

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(
                executor.map(rotate, ("concurrent-a", "concurrent-b"))
            )

        successes = [value for state, value in outcomes if state == "success"]
        failures = [value for state, value in outcomes if state == "error"]
        self.assertEqual(len(successes), 1, outcomes)
        self.assertEqual(failures, ["refresh_reused"])
        with error_code(self, "invalid_token"):
            self.service.authenticate_access(
                token_from(successes[0], "access_token")
            )

    def test_many_refreshes_keep_token_rows_bounded(self) -> None:
        self.service.rate_limiter = RateLimiter(
            clock=self.clock,
            limit=1_000,
            window_ms=60_000,
        )
        current = registration(self.service)
        for index in range(50):
            self.clock.advance(60_001)
            current = self.service.refresh(
                refresh_token=token_from(current, "refresh_token"),
                installation_id="installation-a",
                request_id=f"bounded-refresh-{index}",
            )

        with closing(sqlite3.connect(self.service.repository.path)) as database:
            access_count = database.execute(
                "SELECT COUNT(*) FROM auth_access_tokens"
            ).fetchone()[0]
            refresh_count = database.execute(
                "SELECT COUNT(*) FROM auth_refresh_tokens"
            ).fetchone()[0]
        self.assertLessEqual(access_count, 2)
        self.assertEqual(refresh_count, 2)

    def test_refresh_rate_limit_is_stable_across_token_rotation(self) -> None:
        current = registration(self.service)
        self.service.rate_limiter = RateLimiter(
            clock=self.clock,
            policies={
                "refresh-ip": RatePolicy(100, 60_000),
                "refresh-session": RatePolicy(2, 60_000),
            },
        )
        for index in range(2):
            current = self.service.refresh(
                refresh_token=token_from(current, "refresh_token"),
                installation_id="installation-a",
                request_id=f"stable-session-{index}",
            )

        with error_code(self, "rate_limited"):
            self.service.refresh(
                refresh_token=token_from(current, "refresh_token"),
                installation_id="installation-a",
                request_id="stable-session-limited",
            )

    def test_login_replaces_same_installation_and_caps_active_sessions(self) -> None:
        original = registration(self.service, installation_id="installation-0")
        self.service.rate_limiter = RateLimiter(
            clock=self.clock,
            limit=1_000,
            window_ms=60_000,
        )
        replacement = self.service.login(
            email="reader@example.com",
            password=PASSWORD,
            installation_id="installation-0",
        )
        with error_code(self, "invalid_token"):
            self.service.authenticate_access(token_from(original, "access_token"))
        self.assertEqual(
            self.service.authenticate_access(
                token_from(replacement, "access_token")
            ).account_id,
            account_from(original)["id"],
        )

        oldest_retained_access = token_from(replacement, "access_token")
        for index in range(1, MAX_ACTIVE_SESSIONS_PER_ACCOUNT + 1):
            self.clock.advance(1)
            self.service.login(
                email="reader@example.com",
                password=PASSWORD,
                installation_id=f"installation-{index}",
            )

        with closing(sqlite3.connect(self.service.repository.path)) as database:
            active = database.execute(
                "SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL"
            ).fetchone()[0]
        self.assertEqual(active, MAX_ACTIVE_SESSIONS_PER_ACCOUNT)
        with error_code(self, "invalid_token"):
            self.service.authenticate_access(oldest_retained_access)

    def test_future_auth_schema_version_fails_closed(self) -> None:
        database = Path(self.temporary.name) / "future-schema.sqlite3"
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.execute(
                "CREATE TABLE auth_schema_migrations("
                "version INTEGER PRIMARY KEY,applied_at INTEGER NOT NULL)"
            )
            connection.execute(
                "INSERT INTO auth_schema_migrations(version,applied_at) VALUES(?,0)",
                (SUPPORTED_AUTH_SCHEMA_VERSION + 1,),
            )

        with self.assertRaisesRegex(RuntimeError, "newer auth schema"):
            AuthRepository(database)

    def test_repository_ping_requires_the_existing_current_schema(self) -> None:
        database = Path(self.temporary.name) / "readiness.sqlite3"
        repository = AuthRepository(database)
        self.assertTrue(repository.ping())

        database.unlink()
        self.assertFalse(repository.ping())
        self.assertFalse(database.exists())

        with closing(sqlite3.connect(database)) as connection, connection:
            connection.execute(
                "CREATE TABLE auth_schema_migrations("
                "version INTEGER PRIMARY KEY,applied_at INTEGER NOT NULL)"
            )
            connection.execute(
                "INSERT INTO auth_schema_migrations(version,applied_at) "
                "VALUES(?,0)",
                (SUPPORTED_AUTH_SCHEMA_VERSION,),
            )
        self.assertFalse(repository.ping())

    def test_repository_ping_requires_a_writable_sqlite_path(self) -> None:
        root = Path(self.temporary.name) / "read-only-parent"
        database = root / "accounts.sqlite3"
        repository = AuthRepository(database)
        self.assertTrue(repository.ping())

        root.chmod(0o500)
        try:
            self.assertFalse(repository.ping())
        finally:
            root.chmod(0o700)

    def test_logout_revokes_access_and_refresh_token(self) -> None:
        tokens = registration(self.service)
        access = token_from(tokens, "access_token")
        refresh = token_from(tokens, "refresh_token")

        self.service.logout(access)

        with error_code(self, "invalid_token"):
            self.service.authenticate_access(access)
        with error_code(self, "refresh_expired"):
            self.service.refresh(
                refresh_token=refresh,
                installation_id="installation-a",
                request_id="refresh-after-logout",
            )

    def test_database_stores_only_fixed_length_token_digests(self) -> None:
        tokens = registration(self.service)
        access = token_from(tokens, "access_token")
        refresh = token_from(tokens, "refresh_token")

        with closing(sqlite3.connect(self.service.repository.path)) as database:
            stored_access = database.execute(
                "SELECT token_digest FROM auth_access_tokens"
            ).fetchone()[0]
            stored_refresh = database.execute(
                "SELECT token_digest FROM auth_refresh_tokens"
            ).fetchone()[0]

        self.assertIsInstance(stored_access, bytes)
        self.assertIsInstance(stored_refresh, bytes)
        self.assertEqual(len(stored_access), 32)
        self.assertEqual(len(stored_refresh), 32)
        self.assertNotEqual(stored_access, access.encode())
        self.assertNotEqual(stored_refresh, refresh.encode())
        database_bytes = Path(self.service.repository.path).read_bytes()
        self.assertNotIn(access.encode(), database_bytes)
        self.assertNotIn(refresh.encode(), database_bytes)

    def test_suspending_account_revokes_all_existing_credentials(self) -> None:
        tokens = registration(self.service)
        access = token_from(tokens, "access_token")
        refresh = token_from(tokens, "refresh_token")
        account_id = account_from(tokens)["id"]

        self.service.repository.set_account_status(
            account_id,
            "suspended",
            self.clock(),
        )

        with error_code(self, "invalid_token"):
            self.service.authenticate_access(access)
        with error_code(self, "refresh_expired"):
            self.service.refresh(
                refresh_token=refresh,
                installation_id="installation-a",
                request_id="refresh-after-suspension",
            )


if __name__ == "__main__":
    unittest.main()
