"""Locked, capacity-aware, atomically published SQLite backups."""

from __future__ import annotations

import fcntl
import hashlib
import os
import re
import shutil
import sqlite3
import stat
import uuid
from contextlib import closing, contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Iterator

from .backup_verification import (
    BackupVerificationError,
    verify_database as _verify_database,
    verify_generation,
    write_generation_metadata,
)

_LOCK = ".backup.lock"


class BackupBusyError(RuntimeError):
    """Another backup process owns the destination lock."""


class BackupCapacityError(RuntimeError):
    """The destination cannot hold a new generation and its reserve."""


class BackupManager:
    def __init__(
        self,
        *,
        retention: int = 14,
        minimum_free_bytes: int = 1024 * 1024 * 1024,
        now: Callable[[], datetime] | None = None,
    ):
        if retention <= 0:
            raise ValueError("backup retention must be positive")
        if minimum_free_bytes < 0:
            raise ValueError("backup destination reserve must not be negative")
        self.retention = retention
        self.minimum_free_bytes = minimum_free_bytes
        self.now = now or (lambda: datetime.now(timezone.utc))

    def create(
        self,
        auth_database: Path,
        tenant_databases: Iterable[Path],
        destination: Path,
    ) -> Path:
        sources = (Path(auth_database),) + tuple(
            sorted(Path(path) for path in tenant_databases)
        )
        _require_regular_file(sources[0], "auth database")
        for source in sources[1:]:
            _require_regular_file(source, "tenant database")
            if not re.fullmatch(r"account-[0-9a-f]{64}\.sqlite3", source.name):
                raise BackupVerificationError("tenant database name is invalid")

        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        with _exclusive_lock(destination):
            self._require_capacity(sources, destination)
            completed = self._create_generation(sources, destination)
            self._rotate(destination, protected=completed)
            return completed

    def _create_generation(
        self,
        sources: tuple[Path, ...],
        destination: Path,
    ) -> Path:
        name = self._generation_name()
        partial = destination / f"{name}.partial"
        completed = destination / name
        partial.mkdir(mode=0o700)
        published = False

        try:
            records = [self._copy(sources[0], partial / "accounts.sqlite3", partial)]
            tenant_target = partial / "accounts"
            tenant_target.mkdir(mode=0o700)
            for source in sources[1:]:
                records.append(
                    self._copy(source, tenant_target / source.name, partial)
                )

            _fsync_directory(tenant_target)
            self._write_metadata(partial, records)
            _fsync_directory(partial)
            os.replace(partial, completed)
            published = True
            _fsync_directory(destination)
        except BaseException:
            shutil.rmtree(partial, ignore_errors=True)
            if published:
                shutil.rmtree(completed, ignore_errors=True)
            raise
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

    def _write_metadata(self, partial: Path, records: list[dict]) -> None:
        write_generation_metadata(
            partial,
            {
                "format": 1,
                "created_at": self.now().astimezone(timezone.utc).isoformat(),
                "consistency": "individual_sqlite_snapshots",
                "databases": sorted(records, key=lambda item: item["path"]),
            },
        )

    def _generation_name(self) -> str:
        timestamp = self.now().astimezone(timezone.utc).strftime(
            "%Y%m%dT%H%M%S.%fZ"
        )
        return f"comicollect-{timestamp}-{uuid.uuid4().hex[:8]}"

    def _require_capacity(
        self,
        sources: tuple[Path, ...],
        destination: Path,
    ) -> None:
        estimate = sum(_source_footprint(source) for source in sources)
        available = shutil.disk_usage(destination).free
        if available < estimate + self.minimum_free_bytes:
            raise BackupCapacityError(
                "backup destination lacks space for the estimated generation "
                "and configured reserve"
            )

    def _rotate(self, destination: Path, *, protected: Path) -> None:
        protected_manifest = verify_generation(protected)
        generations: list[tuple[datetime, Path]] = []
        for path in destination.glob("comicollect-*"):
            if not path.is_dir() or path.name.endswith(".partial"):
                continue
            try:
                manifest = (
                    protected_manifest
                    if path == protected
                    else verify_generation(path)
                )
                created_at = datetime.fromisoformat(manifest["created_at"])
            except (OSError, BackupVerificationError, TypeError, ValueError):
                continue
            generations.append((created_at, path))

        generations.sort(key=lambda item: (item[0], item[1].name), reverse=True)
        keep = {protected}
        for _, path in generations:
            if len(keep) >= self.retention:
                break
            keep.add(path)
        for _, stale in generations:
            if stale not in keep:
                shutil.rmtree(stale)
        _fsync_directory(destination)


def _backup_database(source: Path, target: Path) -> None:
    source_uri = source.resolve().as_uri() + "?mode=ro"
    with closing(
        sqlite3.connect(source_uri, uri=True, timeout=15)
    ) as source_db, closing(sqlite3.connect(target, timeout=15)) as target_db:
        source_db.execute("PRAGMA busy_timeout=15000")
        source_db.backup(target_db)


def _hash_and_sync(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb+") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
        os.fsync(stream.fileno())
    return digest.hexdigest(), size


def _source_footprint(database: Path) -> int:
    return sum(
        candidate.stat().st_size
        for candidate in (
            database,
            Path(f"{database}-wal"),
            Path(f"{database}-shm"),
        )
        if candidate.exists()
    )


@contextmanager
def _exclusive_lock(destination: Path) -> Iterator[None]:
    descriptor = os.open(destination / _LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise BackupBusyError("another backup process is already running") from error
        yield
    finally:
        os.close(descriptor)


def _require_regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise FileNotFoundError(f"{label} does not exist: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise BackupVerificationError(f"{label} must be a regular file: {path}")


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
