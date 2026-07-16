"""Verified, atomically published backups for the single-node backend."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable

_MANIFEST = "manifest.json"


class BackupManager:
    def __init__(
        self,
        *,
        retention: int = 14,
        now: Callable[[], datetime] | None = None,
    ):
        if retention <= 0:
            raise ValueError("backup retention must be positive")
        self.retention = retention
        self.now = now or (lambda: datetime.now(timezone.utc))

    def create(
        self,
        auth_database: Path,
        tenant_databases: Iterable[Path],
        destination: Path,
    ) -> Path:
        auth_database = Path(auth_database)
        if not auth_database.is_file():
            raise FileNotFoundError(f"auth database does not exist: {auth_database}")

        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        name = self._generation_name()
        partial = destination / f"{name}.partial"
        completed = destination / name
        partial.mkdir(mode=0o700)
        published = False

        try:
            records = [
                self._copy(auth_database, partial / "accounts.sqlite3", partial)
            ]
            tenant_target = partial / "accounts"
            tenant_target.mkdir(mode=0o700)
            for source in sorted(Path(path) for path in tenant_databases):
                if not source.is_file():
                    raise FileNotFoundError(
                        f"tenant database does not exist: {source}"
                    )
                records.append(
                    self._copy(source, tenant_target / source.name, partial)
                )

            _fsync_directory(tenant_target)
            self._write_manifest(partial, records)
            _fsync_directory(partial)
            os.replace(partial, completed)
            published = True
            _fsync_directory(destination)
        except BaseException:
            shutil.rmtree(partial, ignore_errors=True)
            if published:
                shutil.rmtree(completed, ignore_errors=True)
            raise

        self._rotate(destination)
        return completed

    def _copy(self, source: Path, target: Path, root: Path) -> dict:
        _backup_database(source, target)
        _verify_database(target)
        target.chmod(0o600)
        digest, size = _hash_and_sync(target)
        return {
            "path": target.relative_to(root).as_posix(),
            "sha256": digest,
            "size": size,
        }

    def _write_manifest(self, partial: Path, records: list[dict]) -> None:
        manifest = {
            "format": 1,
            "created_at": self.now().astimezone(timezone.utc).isoformat(),
            "consistency": "individual_sqlite_snapshots",
            "databases": sorted(records, key=lambda item: item["path"]),
        }
        path = partial / _MANIFEST
        payload = json.dumps(
            manifest,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        with path.open("x", encoding="utf-8") as stream:
            stream.write(payload)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        path.chmod(0o600)

    def _generation_name(self) -> str:
        timestamp = self.now().astimezone(timezone.utc).strftime(
            "%Y%m%dT%H%M%S.%fZ"
        )
        return f"comicollect-{timestamp}-{uuid.uuid4().hex[:8]}"

    def _rotate(self, destination: Path) -> None:
        completed = sorted(
            (
                path
                for path in destination.glob("comicollect-*")
                if path.is_dir()
                and not path.name.endswith(".partial")
                and (path / _MANIFEST).is_file()
            ),
            reverse=True,
        )
        for stale in completed[self.retention :]:
            shutil.rmtree(stale)


def _backup_database(source: Path, target: Path) -> None:
    source_uri = source.resolve().as_uri() + "?mode=ro"
    with closing(
        sqlite3.connect(source_uri, uri=True, timeout=15)
    ) as source_db, closing(sqlite3.connect(target, timeout=15)) as target_db:
        source_db.execute("PRAGMA busy_timeout=15000")
        source_db.backup(target_db)


def _verify_database(path: Path) -> None:
    uri = path.resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=15)) as database:
        result = [row[0] for row in database.execute("PRAGMA quick_check")]
    if result != ["ok"]:
        raise RuntimeError(f"backup quick_check failed: {path.name}")


def _hash_and_sync(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb+") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
        os.fsync(stream.fileno())
    return digest.hexdigest(), size


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
