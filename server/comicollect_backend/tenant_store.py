"""Lazy registry of completely isolated Sync v2 stores."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
from collections import OrderedDict
from contextlib import closing, contextmanager
from pathlib import Path
from threading import Condition, Lock
from typing import Iterator

from .api_errors import PublicApiError
from .backup import BackupManager


_WRITE_BASE_RESERVATION_BYTES = 16 * 1024 * 1024
_WRITE_PAYLOAD_MULTIPLIER = 4


class TenantStorageError(PublicApiError):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(status, code, message)


class TenantStore:
    def __init__(
        self,
        root: Path | str,
        *,
        maximum_cached_stores: int = 256,
        maximum_tenant_bytes: int = 512 * 1024 * 1024,
        minimum_free_bytes: int = 1024 * 1024 * 1024,
    ):
        if min(
            maximum_cached_stores,
            maximum_tenant_bytes,
            minimum_free_bytes,
        ) <= 0:
            raise ValueError("tenant store limits must be positive")
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.root.chmod(0o700)
        self.maximum_cached_stores = maximum_cached_stores
        self.maximum_tenant_bytes = maximum_tenant_bytes
        self.minimum_free_bytes = minimum_free_bytes
        self._stores: OrderedDict[str, object] = OrderedDict()
        self._lock = Lock()
        self._operations_changed = Condition(self._lock)
        self._active_operations: dict[str, int] = {}
        self._blocked_accounts: set[str] = set()
        self._capacity_lock = Lock()
        self._tenant_reservations: dict[str, int] = {}
        self._global_reservation = 0

    def database_path(self, account_id: str) -> Path:
        if not isinstance(account_id, str) or not account_id:
            raise ValueError("account_id is required")
        name = hashlib.sha256(account_id.encode("utf-8")).hexdigest()
        return self.root / f"account-{name}.sqlite3"

    def sync(self, account_id: str, payload: dict) -> dict:
        validated = _validated_v2_payload(payload)
        with self._account_operation(account_id):
            pull_only = not validated["mutations"]
            database_exists = self.database_path(account_id).is_file()
            if pull_only and database_exists:
                return self._store(account_id).sync_v2(
                    validated,
                    cache_response=False,
                )
            reservation = _write_reservation_bytes(validated)
            with self._reserve_capacity(account_id, reservation):
                return self._store(account_id).sync_v2(
                    validated,
                    cache_response=not pull_only,
                )

    def sync_v1(self, account_id: str, since: int, changes: list[dict]):
        with self._account_operation(account_id):
            reservation = _write_reservation_bytes(changes)
            with self._reserve_capacity(account_id, reservation):
                return self._store(account_id).sync(since, changes)

    def server_id(self, account_id: str) -> str:
        with self._account_operation(account_id):
            return self._store(account_id).server_id

    def export_snapshot(self, account_id: str) -> dict:
        """Return the canonical, user-owned Sync v2 state only."""

        with self._account_operation(account_id):
            database = self.database_path(account_id)
            if not database.is_file():
                return {"server_id": None, "revision": 0, "entities": []}
            store = self._store(account_id)
            with store.lock, closing(store.connect()) as connection:
                server = connection.execute(
                    "SELECT value FROM sync_meta WHERE key='server_id'"
                ).fetchone()
                revision = connection.execute(
                    "SELECT COALESCE(MAX(revision),0) FROM v2_change_groups"
                ).fetchone()[0]
                rows = connection.execute(
                    "SELECT entity_type,entity_id,operation,data_json,revision "
                    "FROM v2_entities ORDER BY entity_type,entity_id"
                ).fetchall()
            return {
                "server_id": None if server is None else str(server[0]),
                "revision": int(revision),
                "entities": [
                    {
                        "entity_type": str(row["entity_type"]),
                        "entity_id": str(row["entity_id"]),
                        "operation": str(row["operation"]),
                        "data": json.loads(row["data_json"]),
                        "revision": int(row["revision"]),
                    }
                    for row in rows
                ],
            }

    def erase_account(self, account_id: str) -> None:
        """Block future work and remove one tenant database and its sidecars."""

        with self._operations_changed:
            self._blocked_accounts.add(account_id)
            self._operations_changed.notify_all()
            while self._active_operations.get(account_id, 0):
                self._operations_changed.wait()
            self._stores.pop(account_id, None)
        try:
            database = self.database_path(account_id)
            for candidate in (
                database,
                Path(f"{database}-wal"),
                Path(f"{database}-shm"),
            ):
                try:
                    candidate.unlink()
                except FileNotFoundError:
                    continue
        except BaseException:
            with self._operations_changed:
                self._blocked_accounts.discard(account_id)
                self._operations_changed.notify_all()
            raise

    def ready(self) -> bool:
        descriptor: int | None = None
        probe: str | None = None
        try:
            descriptor, probe = tempfile.mkstemp(prefix=".ready-", dir=self.root)
            payload = b"ready\n"
            if os.write(descriptor, payload) != len(payload):
                raise OSError("tenant readiness probe write was incomplete")
            os.fsync(descriptor)
            os.close(descriptor)
            descriptor = None
            os.unlink(probe)
            probe = None
            return shutil.disk_usage(self.root).free >= self.minimum_free_bytes
        except OSError:
            return False
        finally:
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            if probe is not None:
                try:
                    os.unlink(probe)
                except OSError:
                    pass

    def backup_all(self, auth_database: Path, destination: Path | str) -> Path:
        return BackupManager().create(
            Path(auth_database),
            self.root.glob("account-*.sqlite3"),
            Path(destination),
        )

    def _store(self, account_id: str):
        with self._lock:
            if account_id in self._blocked_accounts:
                raise TenantStorageError(
                    410,
                    "account_deleting",
                    "Account deletion is in progress",
                )
            store = self._stores.pop(account_id, None)
            if store is None:
                # Lazy import avoids a cycle with the compatibility launcher.
                try:
                    from comicollect_server import Store
                except ModuleNotFoundError:  # Imported as server.comicollect_backend.
                    from server.comicollect_server import Store

                store = Store(self.database_path(account_id))
                self.database_path(account_id).chmod(0o600)
            self._stores[account_id] = store
            while len(self._stores) > self.maximum_cached_stores:
                self._stores.popitem(last=False)
            return store

    @contextmanager
    def _account_operation(self, account_id: str) -> Iterator[None]:
        with self._operations_changed:
            if account_id in self._blocked_accounts:
                raise TenantStorageError(
                    410,
                    "account_deleting",
                    "Account deletion is in progress",
                )
            self._active_operations[account_id] = (
                self._active_operations.get(account_id, 0) + 1
            )
        try:
            yield
        finally:
            with self._operations_changed:
                remaining = self._active_operations[account_id] - 1
                if remaining:
                    self._active_operations[account_id] = remaining
                else:
                    del self._active_operations[account_id]
                self._operations_changed.notify_all()

    @contextmanager
    def _reserve_capacity(
        self,
        account_id: str,
        reservation: int,
    ) -> Iterator[None]:
        database = self.database_path(account_id)
        with self._capacity_lock:
            allocated = _allocated_bytes(database)
            tenant_reserved = self._tenant_reservations.get(account_id, 0)
            if (
                allocated + tenant_reserved + reservation
                > self.maximum_tenant_bytes
            ):
                raise TenantStorageError(
                    507,
                    "tenant_storage_limit",
                    "Account storage limit has been reached",
                )
            free = shutil.disk_usage(self.root).free
            if (
                free - self._global_reservation - reservation
                < self.minimum_free_bytes
            ):
                raise TenantStorageError(
                    503,
                    "storage_reserve_reached",
                    "Server storage reserve has been reached",
                )
            self._tenant_reservations[account_id] = (
                tenant_reserved + reservation
            )
            self._global_reservation += reservation
        try:
            yield
        finally:
            with self._capacity_lock:
                remaining = self._tenant_reservations[account_id] - reservation
                if remaining:
                    self._tenant_reservations[account_id] = remaining
                else:
                    del self._tenant_reservations[account_id]
                self._global_reservation -= reservation


def _allocated_bytes(database: Path) -> int:
    total = 0
    for candidate in (
        database,
        Path(f"{database}-wal"),
        Path(f"{database}-shm"),
    ):
        try:
            total += candidate.stat().st_size
        except FileNotFoundError:
            continue
    return total


def _write_reservation_bytes(payload: object) -> int:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return _WRITE_BASE_RESERVATION_BYTES + (
        len(encoded) * _WRITE_PAYLOAD_MULTIPLIER
    )


def _validated_v2_payload(payload: object) -> dict:
    # Lazy import keeps the compatibility Store independent from this registry.
    try:
        from comicollect_server import SyncValidationError, validate_v2_request
    except ModuleNotFoundError:
        from server.comicollect_server import (
            SyncValidationError,
            validate_v2_request,
        )

    try:
        return validate_v2_request(payload)
    except (TypeError, ValueError, OverflowError) as exc:
        raise SyncValidationError() from exc
