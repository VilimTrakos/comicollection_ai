from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_service import AuthService

from tests.support import PEPPER, make_hasher


class ProductionBackupCliTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.server = Path(__file__).parents[1]

    def environment(self, pepper: bytes = PEPPER) -> dict[str, str]:
        pepper_file = self.root / f"pepper-{pepper[:1].hex()}"
        pepper_file.write_bytes(pepper)
        environment = dict(os.environ)
        environment.pop("COMICOLLECT_PASSWORD_PEPPER", None)
        environment.update(
            {
                "COMICOLLECT_DATA_ROOT": str(self.root / "data"),
                "COMICOLLECT_PASSWORD_PEPPER_FILE": str(pepper_file),
                "COMICOLLECT_PUBLIC_REGISTRATION": "false",
            }
        )
        return environment

    def command(self, environment: dict[str, str], backup: Path):
        return subprocess.run(
            [
                sys.executable,
                "comicollect_server.py",
                "--mode",
                "production",
                "--backup",
                "--backup-dir",
                str(backup),
            ],
            cwd=self.server,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def initialize_auth_graph(self) -> Path:
        database = self.root / "data" / "accounts.sqlite3"
        AuthService(AuthRepository(database), make_hasher())
        return database

    def test_cli_validates_auth_graph_then_creates_verified_generation(self) -> None:
        self.initialize_auth_graph()
        destination = self.root / "backups"

        result = self.command(self.environment(), destination)

        self.assertEqual(result.returncode, 0, result.stderr)
        generation = Path(result.stdout.strip())
        self.assertTrue(generation.is_dir())
        self.assertTrue((generation / "accounts.sqlite3").is_file())
        self.assertTrue((generation / "manifest.json").is_file())

    def test_cli_does_not_create_a_backup_database_when_auth_is_missing(self) -> None:
        destination = self.root / "backups"
        auth_database = self.root / "data" / "accounts.sqlite3"

        result = self.command(self.environment(), destination)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires an existing auth database", result.stderr)
        self.assertFalse(auth_database.exists())
        self.assertFalse(destination.exists())

    def test_cli_rejects_wrong_pepper_before_copying_any_database(self) -> None:
        self.initialize_auth_graph()
        destination = self.root / "backups"

        result = self.command(self.environment(b"x" * 32), destination)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("backup validation failed", result.stderr)
        self.assertIn("token key does not match", result.stderr)
        self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
