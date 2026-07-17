from __future__ import annotations

import fcntl
import hashlib
import json
import os
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
from threading import Event
from unittest.mock import patch

from comicollect_backend import backup as backup_module
from comicollect_backend import tenant_store as tenant_store_module
from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.backup import (
    BackupBusyError,
    BackupCapacityError,
    BackupManager,
    BackupVerificationError,
    verify_generation,
)
from comicollect_backend.api_errors import PublicApiError
from comicollect_backend.tenant_store import (
    TenantStorageError,
    TenantStore,
    _write_reservation_bytes,
)

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
        with self.assertRaises(PublicApiError) as raised:
            self.store.sync("account-a", request)
        self.assertEqual(raised.exception.code, "invalid_request")

    def test_tenant_database_file_name_does_not_expose_account_identifier(self) -> None:
        path = self.store.database_path("private-account-identifier")
        self.assertNotIn("private-account-identifier", path.name)
        self.assertRegex(path.name, r"^account-[0-9a-f]{64}\.sqlite3$")

    def test_privacy_export_contains_only_canonical_account_state(self) -> None:
        self.assertEqual(
            self.store.export_snapshot("account-empty"),
            {"server_id": None, "revision": 0, "entities": []},
        )
        self.assertFalse(self.store.database_path("account-empty").exists())

        synced = self.store.sync(
            "account-a",
            v2_mutation_request("Portable private title"),
        )
        exported = self.store.export_snapshot("account-a")

        self.assertEqual(exported["server_id"], synced["server_id"])
        self.assertEqual(exported["revision"], 1)
        self.assertEqual(len(exported["entities"]), 1)
        self.assertEqual(
            exported["entities"][0]["data"]["title"],
            "Portable private title",
        )
        self.assertNotIn("mutation_id", exported["entities"][0])
        self.assertNotIn("request_id", exported["entities"][0])

    def test_erasing_account_removes_storage_and_permanently_blocks_work(self) -> None:
        self.store.sync("account-a", v2_mutation_request("Erase me"))
        database = self.store.database_path("account-a")
        Path(f"{database}-wal").touch()
        Path(f"{database}-shm").touch()

        self.store.erase_account("account-a")

        self.assertFalse(database.exists())
        self.assertFalse(Path(f"{database}-wal").exists())
        self.assertFalse(Path(f"{database}-shm").exists())
        for operation in (
            lambda: self.store.export_snapshot("account-a"),
            lambda: self.store.sync(
                "account-a",
                empty_v2_request("blocked-after-erasure"),
            ),
        ):
            with self.assertRaises(TenantStorageError) as blocked:
                operation()
            self.assertEqual(blocked.exception.code, "account_deleting")

    def test_erasure_waits_for_in_flight_sync_and_blocks_new_work(self) -> None:
        entered = Event()
        release = Event()

        class BlockingStore:
            def sync_v2(self, payload, *, cache_response=True):
                entered.set()
                release.wait(timeout=5)
                return {"ok": True}

        with patch.object(self.store, "_store", return_value=BlockingStore()):
            with ThreadPoolExecutor(max_workers=2) as executor:
                active = executor.submit(
                    self.store.sync,
                    "account-a",
                    v2_mutation_request("In flight"),
                )
                self.assertTrue(entered.wait(timeout=5))
                erasure = executor.submit(self.store.erase_account, "account-a")
                with self.store._operations_changed:
                    self.assertTrue(
                        self.store._operations_changed.wait_for(
                            lambda: "account-a" in self.store._blocked_accounts,
                            timeout=5,
                        )
                    )
                self.assertFalse(erasure.done())
                with self.assertRaises(TenantStorageError) as blocked:
                    self.store.sync(
                        "account-a",
                        empty_v2_request("blocked-during-erasure"),
                    )
                self.assertEqual(blocked.exception.code, "account_deleting")
                release.set()
                self.assertEqual(active.result(timeout=5), {"ok": True})
                erasure.result(timeout=5)

    def test_write_limits_preserve_existing_tenant_pulls(self) -> None:
        stored = self.store.sync("account-a", v2_mutation_request("Stored"))
        quota_limited = TenantStore(
            self.store.root,
            maximum_tenant_bytes=1,
            minimum_free_bytes=1,
        )
        pulled = quota_limited.sync(
            "account-a",
            empty_v2_request(
                "quota-pull",
                server_id=stored["server_id"],
            ),
        )
        self.assertEqual(group_titles(pulled), ["Stored"])
        with closing(
            sqlite3.connect(quota_limited.database_path("account-a"))
        ) as database:
            self.assertEqual(
                database.execute("SELECT COUNT(*) FROM v2_requests").fetchone()[0],
                1,
            )
        with self.assertRaises(TenantStorageError) as quota:
            quota_limited.sync(
                "account-a",
                v2_mutation_request(
                    "Blocked",
                    request_id="quota-write",
                    mutation_id="quota-mutation",
                ),
            )
        self.assertEqual(quota.exception.status, 507)
        self.assertEqual(quota.exception.code, "tenant_storage_limit")

        reserve_root = Path(self.temporary.name) / "reserve"
        seeded = TenantStore(reserve_root, minimum_free_bytes=1)
        reserve_state = seeded.sync(
            "account-b",
            v2_mutation_request("Reserved host data"),
        )
        reserve_limited = TenantStore(
            reserve_root,
            minimum_free_bytes=10**30,
        )
        self.assertFalse(reserve_limited.ready())
        pulled = reserve_limited.sync(
            "account-b",
            empty_v2_request(
                "reserve-pull",
                server_id=reserve_state["server_id"],
            ),
        )
        self.assertEqual(group_titles(pulled), ["Reserved host data"])
        with self.assertRaises(TenantStorageError) as reserve:
            reserve_limited.sync(
                "account-b",
                v2_mutation_request(
                    "Blocked by reserve",
                    request_id="reserve-write",
                    mutation_id="reserve-mutation",
                ),
            )
        self.assertEqual(reserve.exception.status, 503)
        self.assertEqual(reserve.exception.code, "storage_reserve_reached")

    def test_readiness_uses_unique_durable_probes_and_removes_them(self) -> None:
        created: list[Path] = []
        real_mkstemp = tempfile.mkstemp

        def record_probe(*args, **kwargs):
            descriptor, name = real_mkstemp(*args, **kwargs)
            created.append(Path(name))
            return descriptor, name

        with patch.object(
            tenant_store_module.tempfile,
            "mkstemp",
            side_effect=record_probe,
        ), patch.object(
            tenant_store_module.os,
            "write",
            wraps=os.write,
        ) as write, patch.object(
            tenant_store_module.os,
            "fsync",
            wraps=os.fsync,
        ) as fsync:
            self.assertTrue(self.store.ready())
            self.assertTrue(self.store.ready())

        self.assertEqual(len(created), 2)
        self.assertNotEqual(created[0], created[1])
        self.assertTrue(all(path.name.startswith(".ready-") for path in created))
        self.assertTrue(all(not path.exists() for path in created))
        self.assertEqual(
            [call.args[1] for call in write.call_args_list],
            [b"ready\n"] * 2,
        )
        self.assertEqual(fsync.call_count, 2)

        with patch.object(
            tenant_store_module.tempfile,
            "mkstemp",
            side_effect=PermissionError("read-only tenant root"),
        ):
            self.assertFalse(self.store.ready())

    def test_concurrent_writes_cannot_spend_the_same_capacity(self) -> None:
        request = v2_mutation_request("Reserved once")
        reservation = _write_reservation_bytes(request)
        store = TenantStore(
            Path(self.temporary.name) / "concurrent-reserve",
            maximum_tenant_bytes=reservation + 1,
            minimum_free_bytes=1,
        )
        entered = Event()
        release = Event()

        class BlockingStore:
            def sync_v2(self, payload, *, cache_response=True):
                entered.set()
                release.wait(timeout=5)
                return {"ok": True}

        with patch.object(store, "_store", return_value=BlockingStore()):
            with ThreadPoolExecutor(max_workers=1) as executor:
                first = executor.submit(store.sync, "account-a", request)
                self.assertTrue(entered.wait(timeout=5))
                try:
                    with self.assertRaises(TenantStorageError) as second:
                        store.sync("account-a", request)
                    self.assertEqual(second.exception.code, "tenant_storage_limit")
                finally:
                    release.set()
                self.assertEqual(first.result(timeout=5), {"ok": True})

    def test_malformed_v1_sync_is_a_safe_public_validation_error(self) -> None:
        with self.assertRaises(PublicApiError) as raised:
            self.store.sync_v1("account-a", 0, [{}])

        self.assertEqual(raised.exception.status, 400)
        self.assertEqual(raised.exception.code, "invalid_request")
        self.assertEqual(str(raised.exception), "Sync payload is invalid")

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
        self.assertTrue((backup / "completion.json").is_file())
        self.assertEqual(verify_generation(backup), manifest)

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

        self.assertFalse(
            any(path.name.endswith(".partial") for path in destination.iterdir())
        )
        self.assertFalse(
            any(
                path.name.startswith("comicollect-")
                for path in destination.iterdir()
            )
        )

    def test_rotation_ignores_a_corrupt_manifest_instead_of_evicting_good_data(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        destination = root / "backups"
        manager = BackupManager(retention=2, minimum_free_bytes=0)
        first = manager.create(auth_database, (), destination)
        second = manager.create(auth_database, (), destination)
        corrupt = destination / "comicollect-99999999T999999Z-corrupt"
        corrupt.mkdir()
        (corrupt / "manifest.json").write_text("{}")
        (corrupt / "completion.json").write_text("{}")
        partial = destination / "comicollect-stale.partial"
        partial.mkdir()
        incomplete = destination / "comicollect-incomplete"
        incomplete.mkdir()

        newest = manager.create(auth_database, (), destination)

        self.assertFalse(first.exists())
        self.assertEqual(verify_generation(second)["format"], 1)
        self.assertEqual(verify_generation(newest)["format"], 1)
        self.assertTrue(corrupt.is_dir())
        self.assertTrue(partial.is_dir())
        self.assertTrue(incomplete.is_dir())

    def test_rotation_full_verifies_content_before_counting_a_generation(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        destination = root / "backups"
        manager = BackupManager(retention=2, minimum_free_bytes=0)
        first = manager.create(auth_database, (), destination)
        corrupt = manager.create(auth_database, (), destination)
        snapshot = corrupt / "accounts.sqlite3"
        content = bytearray(snapshot.read_bytes())
        content[-1] ^= 1
        snapshot.write_bytes(content)

        newest = manager.create(auth_database, (), destination)

        self.assertTrue(first.is_dir())
        self.assertTrue(corrupt.is_dir())
        with self.assertRaisesRegex(BackupVerificationError, "does not match"):
            verify_generation(corrupt)
        self.assertEqual(verify_generation(first)["format"], 1)
        self.assertEqual(verify_generation(newest)["format"], 1)

    def test_full_verification_rejects_manifest_or_database_tampering(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        first = self.store.backup_all(auth_database, root / "backups-a")
        with (first / "manifest.json").open("ab") as stream:
            stream.write(b" ")
        with self.assertRaisesRegex(BackupVerificationError, "completion marker"):
            verify_generation(first)

        second = self.store.backup_all(auth_database, root / "backups-b")
        with (second / "accounts.sqlite3").open("ab") as stream:
            stream.write(b"tampered")
        with self.assertRaisesRegex(BackupVerificationError, "manifest"):
            verify_generation(second)

        third = self.store.backup_all(auth_database, root / "backups-c")
        (third / "accounts" / "untracked.txt").write_text("not in manifest")
        with self.assertRaisesRegex(BackupVerificationError, "unexpected files"):
            verify_generation(third)

    def test_backup_lock_and_destination_reserve_fail_before_copying(self) -> None:
        root = Path(self.temporary.name)
        auth_database = root / "accounts.sqlite3"
        AuthRepository(auth_database)
        destination = root / "backups"
        destination.mkdir()
        descriptor = os.open(
            destination / ".backup.lock",
            os.O_RDWR | os.O_CREAT,
            0o600,
        )
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BackupBusyError):
                BackupManager(minimum_free_bytes=0).create(
                    auth_database,
                    (),
                    destination,
                )
        finally:
            os.close(descriptor)

        with self.assertRaises(BackupCapacityError):
            BackupManager(minimum_free_bytes=10**30).create(
                auth_database,
                (),
                root / "capacity",
            )
        self.assertFalse(
            any(
                path.name.startswith("comicollect-")
                for path in (root / "capacity").iterdir()
            )
        )


if __name__ == "__main__":
    unittest.main()
