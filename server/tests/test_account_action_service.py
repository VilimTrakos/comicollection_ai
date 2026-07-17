from __future__ import annotations

import re
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
from threading import Event

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_service import AuthService

from tests.support import (
    PASSWORD,
    PEPPER,
    MutableClock,
    RecordingEmailSender,
    account_from,
    error_code,
    make_hasher,
    make_auth_service,
    registration,
    token_from,
)


NEW_PASSWORD = "A different secure passphrase 84!"
_ACTION_TOKEN = re.compile(r"\b(?:cce|ccp)_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")


class AccountActionServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.clock = MutableClock()
        self.sender = RecordingEmailSender()
        self.service = make_auth_service(
            Path(self.temporary.name) / "accounts.sqlite3",
            clock=self.clock,
            email_sender=self.sender,
            email_verification_ttl_ms=60_000,
            password_reset_ttl_ms=60_000,
        )
        self.registered = registration(self.service)
        self.context = self.service.authenticate_access(
            token_from(self.registered, "access_token")
        )

    def request_verification(self) -> str:
        self.service.request_email_verification(self.context, rate_key="client-a")
        return _token(self.sender.messages[-1].text_body, "cce_")

    def request_reset(self, email: str = "reader@example.com") -> str:
        self.service.request_password_reset(email, rate_key="client-a")
        return _token(self.sender.messages[-1].text_body, "ccp_")

    def test_email_confirmation_is_idempotent_only_for_the_exact_retry(self) -> None:
        token = self.request_verification()
        arguments = {
            "token": token,
            "request_id": "verification-request-1",
            "rate_key": "client-a",
        }

        first = self.service.confirm_email_verification(self.context, **arguments)
        retry = self.service.confirm_email_verification(self.context, **arguments)

        self.assertTrue(first["account"]["email_verified"])
        self.assertEqual(retry, first)
        with error_code(self, "action_token_invalid"):
            self.service.confirm_email_verification(
                self.context,
                token=token,
                request_id="verification-request-2",
                rate_key="client-a",
            )
        message_count = len(self.sender.messages)
        self.service.request_email_verification(self.context, rate_key="client-a")
        self.assertEqual(len(self.sender.messages), message_count)

    def test_new_verification_supersedes_old_and_unconsumed_token_expires(self) -> None:
        first = self.request_verification()
        second = self.request_verification()

        with error_code(self, "action_token_invalid"):
            self.service.confirm_email_verification(
                self.context,
                token=first,
                request_id="verification-old-token",
                rate_key="client-a",
            )
        self.clock.advance(60_001)
        with error_code(self, "action_token_invalid"):
            self.service.confirm_email_verification(
                self.context,
                token=second,
                request_id="verification-expired",
                rate_key="client-a",
            )

    def test_verification_token_is_bound_to_authenticated_account(self) -> None:
        token = self.request_verification()
        other = registration(self.service, "other@example.com")
        other_context = self.service.authenticate_access(token_from(other, "access_token"))

        with error_code(self, "action_token_invalid"):
            self.service.confirm_email_verification(
                other_context,
                token=token,
                request_id="verification-other-account",
                rate_key="client-b",
            )

    def test_concurrent_exact_email_confirmation_converges(self) -> None:
        token = self.request_verification()

        def confirm(_: int) -> dict:
            return self.service.confirm_email_verification(
                self.context,
                token=token,
                request_id="verification-concurrent",
                rate_key="client-a",
            )

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(confirm, range(2)))
        self.assertEqual(results[0], results[1])
        self.assertTrue(results[0]["account"]["email_verified"])

    def test_password_reset_is_private_and_revokes_every_session_token(self) -> None:
        access = token_from(self.registered, "access_token")
        refresh = token_from(self.registered, "refresh_token")
        second_session = self.service.login(
            email="reader@example.com",
            password=PASSWORD,
            installation_id="installation-b",
        )
        reset_token = self.request_reset()
        arguments = {
            "token": reset_token,
            "new_password": NEW_PASSWORD,
            "request_id": "password-reset-request-1",
            "rate_key": "client-a",
        }

        self.service.confirm_password_reset(**arguments)
        self.service.confirm_password_reset(**arguments)

        with closing(self.service.repository.connect()) as database:
            revoked = database.execute(
                "SELECT COUNT(*) FROM auth_sessions "
                "WHERE revoke_reason='password_reset'"
            ).fetchone()[0]
            access_count = database.execute(
                "SELECT COUNT(*) FROM auth_access_tokens"
            ).fetchone()[0]
            refresh_count = database.execute(
                "SELECT COUNT(*) FROM auth_refresh_tokens"
            ).fetchone()[0]
        self.assertEqual(revoked, 2)
        self.assertEqual((access_count, refresh_count), (0, 0))

        with error_code(self, "invalid_credentials"):
            self.service.login(
                email="reader@example.com",
                password=PASSWORD,
                installation_id="installation-c",
            )
        logged_in = self.service.login(
            email="reader@example.com",
            password=NEW_PASSWORD,
            installation_id="installation-c",
        )
        self.assertEqual(account_from(logged_in)["email"], "reader@example.com")
        for old_access in (access, token_from(second_session, "access_token")):
            with error_code(self, "invalid_token"):
                self.service.authenticate_access(old_access)
        with error_code(self, "invalid_refresh_token"):
            self.service.refresh(
                refresh_token=refresh,
                installation_id="installation-a",
                request_id="refresh-after-password-reset",
            )
        with error_code(self, "action_token_invalid"):
            self.service.confirm_password_reset(
                token=reset_token,
                new_password="Yet another secure passphrase 96!",
                request_id="password-reset-request-1",
                rate_key="client-a",
            )

    def test_unknown_reset_is_indistinguishable_and_sends_nothing(self) -> None:
        self.service.request_password_reset(
            "missing@example.com",
            rate_key="client-a",
        )
        self.service.request_password_reset(
            "not-an-email",
            rate_key="client-a",
        )
        self.assertEqual(self.sender.messages, [])

    def test_registration_rejects_addresses_the_mailer_cannot_deliver(self) -> None:
        for email in ("reader name@example.com", "reader\x7f@example.com"):
            with self.subTest(email=repr(email)), error_code(
                self,
                "invalid_request",
            ):
                self.service.register(
                    email=email,
                    password=PASSWORD,
                    display_name="Reader",
                    installation_id="mailbox-validation",
                    rate_key="mailbox-validation",
                )

    def test_new_reset_supersedes_old_and_unconsumed_token_expires(self) -> None:
        first = self.request_reset()
        second = self.request_reset()
        with error_code(self, "action_token_invalid"):
            self.service.confirm_password_reset(
                token=first,
                new_password=NEW_PASSWORD,
                request_id="reset-old-token",
                rate_key="client-a",
            )
        self.clock.advance(60_001)
        with error_code(self, "action_token_invalid"):
            self.service.confirm_password_reset(
                token=second,
                new_password=NEW_PASSWORD,
                request_id="reset-expired-token",
                rate_key="client-a",
            )

    def test_concurrent_reset_consumption_applies_once(self) -> None:
        token = self.request_reset()

        def confirm(request_id: str) -> str:
            try:
                self.service.confirm_password_reset(
                    token=token,
                    new_password=NEW_PASSWORD,
                    request_id=request_id,
                    rate_key="client-a",
                )
                return "ok"
            except Exception as error:
                return str(getattr(error, "code", "unexpected"))

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(
                executor.map(
                    confirm,
                    ("reset-concurrent-a", "reset-concurrent-b"),
                )
            )
        self.assertCountEqual(results, ["ok", "action_token_invalid"])

    def test_password_reset_wins_over_login_that_verified_the_old_hash(self) -> None:
        repository = _BlockingSessionRepository(
            Path(self.temporary.name) / "login-reset-race.sqlite3"
        )
        sender = RecordingEmailSender()
        service = AuthService(
            repository,
            make_hasher(),
            clock=self.clock,
            token_key=PEPPER,
            registration_enabled=True,
            email_sender=sender,
        )
        registration(service)
        service.request_password_reset(
            "reader@example.com",
            rate_key="reset-client",
        )
        reset_token = _token(sender.messages[-1].text_body, "ccp_")
        repository.block_new_sessions = True

        with ThreadPoolExecutor(max_workers=1) as executor:
            login = executor.submit(
                service.login,
                email="reader@example.com",
                password=PASSWORD,
                installation_id="race-installation",
                rate_key="login-client",
            )
            self.assertTrue(repository.session_entered.wait(timeout=2))
            service.confirm_password_reset(
                token=reset_token,
                new_password=NEW_PASSWORD,
                request_id="reset-wins-login-race",
                rate_key="reset-client",
            )
            repository.allow_session.set()
            with error_code(self, "invalid_credentials"):
                login.result(timeout=2)

        with closing(repository.connect()) as database:
            active = database.execute(
                "SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL"
            ).fetchone()[0]
        self.assertEqual(active, 0)


def _token(body: str, prefix: str) -> str:
    match = _ACTION_TOKEN.search(body)
    if match is None or not match.group(0).startswith(prefix):
        raise AssertionError(f"missing {prefix} action token")
    return match.group(0)


class _BlockingSessionRepository(AuthRepository):
    def __init__(self, path: Path):
        super().__init__(path)
        self.block_new_sessions = False
        self.session_entered = Event()
        self.allow_session = Event()

    def create_session(self, **arguments) -> str:
        if self.block_new_sessions:
            self.session_entered.set()
            if not self.allow_session.wait(timeout=2):
                raise TimeoutError("test session barrier timed out")
        return super().create_session(**arguments)


if __name__ == "__main__":
    unittest.main()
