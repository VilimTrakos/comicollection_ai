"""Lazy registry of completely isolated Sync v2 stores."""

from __future__ import annotations

import hashlib
import shutil
from collections import OrderedDict
from pathlib import Path
from threading import Lock

from .backup import BackupManager


class TenantStorageError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


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

    def database_path(self, account_id: str) -> Path:
        if not isinstance(account_id, str) or not account_id:
            raise ValueError("account_id is required")
        name = hashlib.sha256(account_id.encode("utf-8")).hexdigest()
        return self.root / f"account-{name}.sqlite3"

    def sync(self, account_id: str, payload: dict) -> dict:
        self._require_capacity(account_id)
        return self._store(account_id).sync_v2(payload)

    def sync_v1(self, account_id: str, since: int, changes: list[dict]):
        self._require_capacity(account_id)
        return self._store(account_id).sync(since, changes)

    def server_id(self, account_id: str) -> str:
        return self._store(account_id).server_id

    def ready(self) -> bool:
        probe = self.root / ".ready"
        try:
            probe.touch(exist_ok=True)
            return shutil.disk_usage(self.root).free >= self.minimum_free_bytes
        except OSError:
            return False

    def backup_all(self, auth_database: Path, destination: Path | str) -> Path:
        return BackupManager().create(
            Path(auth_database),
            self.root.glob("account-*.sqlite3"),
            Path(destination),
        )

    def _store(self, account_id: str):
        with self._lock:
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

    def _require_capacity(self, account_id: str) -> None:
        database = self.database_path(account_id)
        allocated = sum(
            candidate.stat().st_size
            for candidate in (
                database,
                Path(f"{database}-wal"),
                Path(f"{database}-shm"),
            )
            if candidate.exists()
        )
        if allocated >= self.maximum_tenant_bytes:
            raise TenantStorageError(
                507,
                "tenant_storage_limit",
                "Account storage limit has been reached",
            )
        if shutil.disk_usage(self.root).free < self.minimum_free_bytes:
            raise TenantStorageError(
                503,
                "storage_reserve_reached",
                "Server storage reserve has been reached",
            )
