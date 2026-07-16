from __future__ import annotations

import hashlib
import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

from comicollect_backend import backup as backup_module
from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.tenant_store import TenantStorageError, TenantStore

from tests.support import empty_v2_request, v2_mutation_request


def group_titles(response: dict) -> list[str]:
    return [
        change["data"]["title"]
        for group in response["change_groups"]
        for change in group["changes"]
        if change["entity_type"] == "custom_issue"
    ]


class TenantStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.store = TenantStore(Path(self.temporary.name) / "tenant.sqlite3")

    def test_same_request_mutation_and_entity_ids_are_isolated_by_account(self) -> None:
        first = self.store.sync("account-a", v2_mutation_request("Account A title"))
        second = self.store.sync("account-b", v2_mutation_request("Account B title"))

        self.assertEqual(first["acknowledgements"][0]["revision"], 1)
        self.assertEqual(second["acknowledgements"][0]["revision"], 1)
        self.assertNotEqual(first["server_id"], second["server_id"])
        self.assertEqual(group_titles(first), ["Account A title"])
        self.assertEqual(group_titles(second), ["Account B title"])

        account_a = self.store.sync(
            "account-a",
            empty_v2_request("pull-a", server_id=first["server_id"]),
        )
        account_b = self.store.sync(
            "account-b",
            empty_v2_request("pull-b", server_id=second["server_id"]),
        )
        self.assertEqual(group_titles(account_a), ["Account A title"])
        self.assertEqual(group_titles(account_b), ["Account B title"])

    def test_revisions_are_contiguous_per_account_when_writes_interleave(self) -> None:
        first_a = self.store.sync(
            "account-a",
            v2_mutation_request(
                "A1",
                request_id="a-request-1",
                mutation_id="a-mutation-1",
            ),
        )
        first_b = self.store.sync(
            "account-b",
            v2_mutation_request(
                "B1",
                request_id="b-request-1",
                mutation_id="b-mutation-1",
            ),
        )
        second_a = self.store.sync(
            "account-a",
            v2_mutation_request(
                "A2",
                request_id="a-request-2",
                mutation_id="a-mutation-2",
                cursor=first_a["next_cursor"],
            ),
        )

        self.assertEqual(first_a["acknowledgements"][0]["revision"], 1)
        self.assertEqual(first_b["acknowledgements"][0]["revision"], 1)
        self.assertEqual(second_a["acknowledgements"][0]["revision"], 2)

    def test_account_scope_is_not_accepted_from_untrusted_payload(self) -> None:
        request = v2_mutation_request("Injected")
        request["account_id"] = "account-b"
        with self.assertRaises(ValueError):
            self.store.sync("account-a", request)

    def test_tenant_database_file_name_does_not_expose_account_identifier(self) -> None:
        path = self.store.database_path("private-account-identifier")
        self.assertNotIn("private-account-identifier", path.name)
        self.assertRegex(path.name, r"^account-[0-9a-f]{64}\.sqlite3$")

    def test_tenant_quota_and_global_disk_reserve_fail_before_sync(self) -> None:
        self.store.sync("account-a", v2_mutation_request("Stored"))
        quota_limited = TenantStore(
            self.store.root,
            maximum_tenant_bytes=1,
            minimum_free_bytes=1,
        )
        with self.assertRaises(TenantStorageError) as quota:
            quota_limited.sync("account-a", empty_v2_request("quota-check"))
        self.assertEqual(quota.exception.status, 507)
        self.assertEqual(quota.exception.code, "tenant_storage_limit")

        reserve_limited = TenantStore(
            Path(self.temporary.name) / "reserve",
            minimum_free_bytes=10**30,
        )
        self.assertFalse(reserve_limited.ready())
        with self.assertRaises(TenantStorageError) as reserve:
            reserve_limited.sync(
                "account-b",
                empty_v2_request("reserve-check"),
            )
        self.assertEqual(reserve.exception.status, 503)
        self.assertEqual(reserve.exception.code, "storage_reserve_reached")

    def test_backup_contains_readable_auth_and_tenant_databases(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        self.store.sync("account-a", v2_mutation_request("Backed up"))

        backup = self.store.backup_all(auth_database, root / "backups")

        databases = [
            backup / "accounts.sqlite3",
            *list((backup / "accounts").glob("*.sqlite3")),
        ]
        self.assertEqual(len(databases), 2)
        manifest = json.loads((backup / "manifest.json").read_text())
        self.assertEqual(manifest["format"], 1)
        self.assertEqual(
            manifest["consistency"],
            "individual_sqlite_snapshots",
        )
        self.assertEqual(
            {record["path"] for record in manifest["databases"]},
            {
                "accounts.sqlite3",
                f"accounts/{databases[1].name}",
            },
        )
        for database in databases:
            with closing(sqlite3.connect(database)) as connection:
                self.assertEqual(
                    connection.execute("PRAGMA quick_check").fetchone()[0],
                    "ok",
                )
            relative = database.relative_to(backup).as_posix()
            record = next(
                item for item in manifest["databases"] if item["path"] == relative
            )
            content = database.read_bytes()
            self.assertEqual(record["size"], len(content))
            self.assertEqual(
                record["sha256"],
                hashlib.sha256(content).hexdigest(),
            )
        self.assertFalse(backup.name.endswith(".partial"))

    def test_backup_fails_closed_when_auth_database_is_missing(self) -> None:
        root = Path(self.temporary.name)
        destination = root / "backups"

        with self.assertRaisesRegex(FileNotFoundError, "auth database"):
            self.store.backup_all(root / "missing.sqlite3", destination)

        self.assertFalse(destination.exists())

    def test_failed_verification_removes_partial_generation(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        self.store.sync("account-a", v2_mutation_request("Backed up"))
        destination = root / "backups"
        verify = backup_module._verify_database

        def fail_tenant(path: Path) -> None:
            verify(path)
            if path.parent.name == "accounts":
                raise RuntimeError("simulated quick_check failure")

        with patch.object(
            backup_module,
            "_verify_database",
            side_effect=fail_tenant,
        ):
            with self.assertRaisesRegex(RuntimeError, "quick_check"):
                self.store.backup_all(auth_database, destination)

        self.assertEqual(list(destination.iterdir()), [])

    def test_rotation_removes_only_completed_verified_generations(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        destination = root / "backups"
        destination.mkdir()
        for index in range(15):
            generation = destination / f"comicollect-20000101T0000{index:02}Z-old"
            generation.mkdir()
            (generation / "manifest.json").write_text("{}")
        partial = destination / "comicollect-stale.partial"
        partial.mkdir()
        incomplete = destination / "comicollect-incomplete"
        incomplete.mkdir()

        self.store.backup_all(auth_database, destination)

        completed = [
            path
            for path in destination.glob("comicollect-*")
            if path.is_dir() and (path / "manifest.json").is_file()
        ]
        self.assertEqual(len(completed), 14)
        self.assertTrue(partial.is_dir())
        self.assertTrue(incomplete.is_dir())


if __name__ == "__main__":
    unittest.main()
