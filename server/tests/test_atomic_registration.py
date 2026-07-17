from __future__ import annotations

import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

from comicollect_backend.auth_repository import AuthRepository

from tests.support import (
    PASSWORD,
    account_from,
    make_auth_service,
    make_hasher,
    registration,
)


class AtomicRegistrationRepositoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = AuthRepository(
            Path(self.temporary.name) / "accounts.sqlite3"
        )

    def test_session_write_failure_rolls_back_account_and_credentials(self) -> None:
        with patch(
            "comicollect_backend.auth_repository._insert_tokens",
            side_effect=sqlite3.OperationalError("simulated token write failure"),
        ):
            with self.assertRaisesRegex(sqlite3.OperationalError, "simulated"):
                self.repository.create_account_with_session(
                    email="rollback@example.com",
                    display_name="Rollback",
                    password_hash=make_hasher().hash(PASSWORD),
                    installation_id="installation-rollback",
                    access_digest=b"a" * 32,
                    access_nonce=b"b" * 32,
                    access_expires_at=1_700_000_060_000,
                    refresh_digest=b"c" * 32,
                    refresh_nonce=b"d" * 32,
                    refresh_expires_at=1_700_000_600_000,
                    session_expires_at=1_700_003_600_000,
                    now=1_700_000_000_000,
                )

        self.assertIsNone(
            self.repository.account_with_password("rollback@example.com")
        )
        with closing(self.repository.connect()) as database:
            counts = tuple(
                database.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                for table in (
                    "accounts",
                    "auth_sessions",
                    "auth_access_tokens",
                    "auth_refresh_tokens",
                )
            )
        self.assertEqual(counts, (0, 0, 0, 0))


class AtomicRegistrationServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.service = make_auth_service(
            Path(self.temporary.name) / "accounts.sqlite3"
        )

    def test_failed_initial_session_leaves_email_available_for_exact_retry(self) -> None:
        with patch(
            "comicollect_backend.auth_repository._insert_tokens",
            side_effect=sqlite3.OperationalError("simulated token write failure"),
        ):
            with self.assertRaises(sqlite3.OperationalError):
                registration(self.service, "retry@example.com")

        self.assertIsNone(
            self.service.repository.account_with_password("retry@example.com")
        )
        created = registration(self.service, "retry@example.com")
        self.assertEqual(account_from(created)["email"], "retry@example.com")

    def test_operator_provisioning_still_creates_an_account_without_a_session(
        self,
    ) -> None:
        account = self.service.provision_account(
            email="operator@example.com",
            password=PASSWORD,
            display_name="Operator",
        )

        self.assertEqual(account["email"], "operator@example.com")
        with closing(self.service.repository.connect()) as database:
            self.assertEqual(
                database.execute("SELECT COUNT(*) FROM accounts").fetchone()[0],
                1,
            )
            self.assertEqual(
                database.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0],
                0,
            )


if __name__ == "__main__":
    unittest.main()
