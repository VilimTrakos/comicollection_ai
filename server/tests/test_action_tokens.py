from __future__ import annotations

import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from comicollect_backend.action_tokens import (
    EMAIL_VERIFICATION,
    PASSWORD_RESET,
    ActionTokenCodec,
)
from comicollect_backend.auth_action_repository import AuthActionRepository
from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_schema import SUPPORTED_AUTH_SCHEMA_VERSION

from tests.support import PASSWORD, PEPPER, make_hasher


class ActionTokenCodecTest(unittest.TestCase):
    def test_tokens_are_random_reconstructable_and_purpose_bound(self) -> None:
        codec = ActionTokenCodec(PEPPER)
        first = codec.create(EMAIL_VERIFICATION)
        second = codec.create(EMAIL_VERIFICATION)

        self.assertNotEqual(first.raw, second.raw)
        self.assertEqual(codec.from_nonce(EMAIL_VERIFICATION, first.nonce), first)
        self.assertEqual(codec.digest(EMAIL_VERIFICATION, first.raw), first.digest)
        with self.assertRaises(ValueError):
            codec.digest(PASSWORD_RESET, first.raw)
        with self.assertRaises(ValueError):
            codec.digest(EMAIL_VERIFICATION, first.raw[:-1] + "A")


class ActionTokenSchemaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / "accounts.sqlite3"

    def test_v2_database_migrates_and_readiness_requires_action_table(self) -> None:
        repository = AuthRepository(self.database)
        account = repository.create_account(
            email="legacy@example.com",
            display_name="Legacy Reader",
            password_hash=make_hasher().hash(PASSWORD),
            now=1_700_000_000_000,
        )
        with closing(repository.connect()) as database, database:
            database.execute("DROP TABLE auth_action_tokens")
            database.execute(
                "DELETE FROM auth_schema_migrations WHERE version=?",
                (SUPPORTED_AUTH_SCHEMA_VERSION,),
            )

        migrated = AuthRepository(self.database)
        self.assertTrue(migrated.ping())
        with closing(migrated.connect()) as database:
            version = database.execute(
                "SELECT MAX(version) FROM auth_schema_migrations"
            ).fetchone()[0]
            columns = {
                row[1]
                for row in database.execute("PRAGMA table_info(auth_action_tokens)")
            }
            verified_at = database.execute(
                "SELECT email_verified_at FROM accounts WHERE id=?",
                (account.id,),
            ).fetchone()[0]
        self.assertEqual(version, SUPPORTED_AUTH_SCHEMA_VERSION)
        self.assertIn("consume_payload_digest", columns)
        self.assertEqual(verified_at, 1_700_000_000_000)

    def test_database_stores_action_digest_and_nonce_but_never_raw_token(self) -> None:
        repository = AuthRepository(self.database)
        account = repository.create_account(
            email="reader@example.com",
            display_name="Reader",
            password_hash=make_hasher().hash(PASSWORD),
            now=1_700_000_000_000,
        )
        codec = ActionTokenCodec(PEPPER)
        token = codec.create(EMAIL_VERIFICATION)
        AuthActionRepository(repository).issue_for_account(
            account_id=account.id,
            purpose=EMAIL_VERIFICATION,
            token_digest=token.digest,
            token_nonce=token.nonce,
            expires_at=1_700_000_060_000,
            now=1_700_000_000_000,
        )

        with closing(repository.connect()) as database:
            row = database.execute(
                "SELECT token_digest,token_nonce FROM auth_action_tokens"
            ).fetchone()
        self.assertEqual(bytes(row[0]), token.digest)
        self.assertEqual(bytes(row[1]), token.nonce)
        self.assertNotIn(token.raw.encode("ascii"), self.database.read_bytes())


if __name__ == "__main__":
    unittest.main()
