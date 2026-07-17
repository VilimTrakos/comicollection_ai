"""Backup completion format and full offline generation verification."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import stat
from contextlib import closing
from datetime import datetime
from pathlib import Path

MANIFEST_NAME = "manifest.json"
COMPLETION_NAME = "completion.json"
_MAX_MANIFEST_BYTES = 4 * 1024 * 1024
_MAX_COMPLETION_BYTES = 4096
_DATABASE_PATH = re.compile(
    r"^(?:accounts\.sqlite3|accounts/account-[0-9a-f]{64}\.sqlite3)$"
)
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


class BackupVerificationError(RuntimeError):
    """A published generation is incomplete or does not match its manifest."""


def write_generation_metadata(root: Path, manifest: dict) -> None:
    """Durably bind a strict completion marker to the exact manifest bytes."""

    manifest_payload = _json_payload(manifest)
    if len(manifest_payload) > _MAX_MANIFEST_BYTES:
        raise BackupVerificationError("backup manifest is too large")
    _write_new_file(root / MANIFEST_NAME, manifest_payload)
    completion_payload = _json_payload(
        {
            "format": 1,
            "manifest_sha256": hashlib.sha256(manifest_payload).hexdigest(),
        }
    )
    _write_new_file(root / COMPLETION_NAME, completion_payload)


def validated_generation_manifest(generation: Path | str) -> dict:
    """Validate completion, manifest schema, exact file set, and byte sizes."""

    root = Path(generation)
    manifest = _load_completed_manifest(root)
    _validate_generation_layout(root, manifest)
    return manifest


def verify_generation(generation: Path | str) -> dict:
    """Also verify every database SHA-256 and SQLite integrity check."""

    root = Path(generation)
    manifest = validated_generation_manifest(root)
    for record in manifest["databases"]:
        database = root / record["path"]
        digest, size = _hash_file(database)
        if size != record["size"] or digest != record["sha256"]:
            raise BackupVerificationError(
                f"backup database does not match manifest: {record['path']}"
            )
        try:
            verify_database(database)
        except (RuntimeError, sqlite3.DatabaseError) as error:
            raise BackupVerificationError(str(error)) from error
    return manifest


def verify_database(path: Path) -> None:
    # Backup files are immutable snapshots. Telling SQLite that explicitly is
    # important for WAL-mode databases: a plain read-only connection may still
    # create ``-wal``/``-shm`` sidecars inside the completed generation.
    uri = path.resolve().as_uri() + "?mode=ro&immutable=1"
    with closing(sqlite3.connect(uri, uri=True, timeout=15)) as database:
        result = [row[0] for row in database.execute("PRAGMA quick_check")]
    if result != ["ok"]:
        raise RuntimeError(f"backup quick_check failed: {path.name}")


def _load_completed_manifest(root: Path) -> dict:
    if not root.is_dir() or root.is_symlink():
        raise BackupVerificationError("backup generation must be a real directory")
    completion_payload = _read_regular_file(
        root / COMPLETION_NAME,
        _MAX_COMPLETION_BYTES,
        "backup completion marker",
    )
    manifest_payload = _read_regular_file(
        root / MANIFEST_NAME,
        _MAX_MANIFEST_BYTES,
        "backup manifest",
    )
    completion = _json_object(completion_payload, "backup completion marker")
    if set(completion) != {"format", "manifest_sha256"}:
        raise BackupVerificationError("backup completion marker has invalid fields")
    digest = completion.get("manifest_sha256")
    if completion.get("format") != 1 or not isinstance(digest, str):
        raise BackupVerificationError("backup completion marker is invalid")
    if not _SHA256.fullmatch(digest):
        raise BackupVerificationError("backup completion digest is invalid")
    if hashlib.sha256(manifest_payload).hexdigest() != digest:
        raise BackupVerificationError("backup manifest does not match completion marker")

    manifest = _json_object(manifest_payload, "backup manifest")
    if set(manifest) != {"format", "created_at", "consistency", "databases"}:
        raise BackupVerificationError("backup manifest has invalid fields")
    if manifest.get("format") != 1:
        raise BackupVerificationError("unsupported backup manifest format")
    if manifest.get("consistency") != "individual_sqlite_snapshots":
        raise BackupVerificationError("unsupported backup consistency model")
    _validate_timestamp(manifest.get("created_at"))
    _validate_records(manifest.get("databases"))
    return manifest


def _validate_timestamp(value: object) -> None:
    if not isinstance(value, str):
        raise BackupVerificationError("backup manifest timestamp is invalid")
    try:
        created_at = datetime.fromisoformat(value)
    except ValueError as error:
        raise BackupVerificationError("backup manifest timestamp is invalid") from error
    if created_at.tzinfo is None:
        raise BackupVerificationError("backup manifest timestamp has no timezone")


def _validate_records(records: object) -> None:
    if not isinstance(records, list) or not records:
        raise BackupVerificationError("backup manifest has no databases")
    seen: set[str] = set()
    for record in records:
        if not isinstance(record, dict) or set(record) != {
            "path",
            "sha256",
            "size",
        }:
            raise BackupVerificationError("backup manifest record is invalid")
        relative = record.get("path")
        digest = record.get("sha256")
        size = record.get("size")
        if not isinstance(relative, str) or not _DATABASE_PATH.fullmatch(relative):
            raise BackupVerificationError("backup manifest contains an unsafe path")
        if relative in seen:
            raise BackupVerificationError("backup manifest contains a duplicate path")
        if not isinstance(digest, str) or not _SHA256.fullmatch(digest):
            raise BackupVerificationError("backup manifest digest is invalid")
        if isinstance(size, bool) or not isinstance(size, int) or size < 0:
            raise BackupVerificationError("backup manifest size is invalid")
        seen.add(relative)
    if "accounts.sqlite3" not in seen:
        raise BackupVerificationError("backup manifest omits the auth database")


def _validate_generation_layout(root: Path, manifest: dict) -> None:
    expected = {record["path"] for record in manifest["databases"]}
    actual = _database_file_set(root)
    if actual != expected:
        raise BackupVerificationError("backup database set does not match manifest")
    for record in manifest["databases"]:
        database = root / record["path"]
        _require_regular_file(database, "backup database")
        if database.stat().st_size != record["size"]:
            raise BackupVerificationError(
                f"backup database size does not match manifest: {record['path']}"
            )


def _database_file_set(root: Path) -> set[str]:
    allowed_root = {
        MANIFEST_NAME,
        COMPLETION_NAME,
        "accounts.sqlite3",
        "accounts",
    }
    if {path.name for path in root.iterdir()} != allowed_root:
        raise BackupVerificationError("backup generation contains unexpected files")
    accounts = root / "accounts"
    if not accounts.is_dir() or accounts.is_symlink():
        raise BackupVerificationError("backup tenant directory is invalid")
    actual: set[str] = set()
    auth = root / "accounts.sqlite3"
    if auth.exists() or auth.is_symlink():
        actual.add("accounts.sqlite3")
    for path in accounts.iterdir():
        if not path.name.endswith(".sqlite3"):
            raise BackupVerificationError("backup tenant directory has unexpected files")
        actual.add(f"accounts/{path.name}")
    return actual


def _hash_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _require_regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise FileNotFoundError(f"{label} does not exist: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise BackupVerificationError(f"{label} must be a regular file: {path}")


def _read_regular_file(path: Path, maximum: int, label: str) -> bytes:
    _require_regular_file(path, label)
    if path.stat().st_size > maximum:
        raise BackupVerificationError(f"{label} is too large")
    return path.read_bytes()


def _json_object(payload: bytes, label: str) -> dict:
    try:
        value = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BackupVerificationError(f"{label} is not valid JSON") from error
    if not isinstance(value, dict):
        raise BackupVerificationError(f"{label} must be a JSON object")
    return value


def _json_payload(value: dict) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _write_new_file(path: Path, payload: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        os.close(descriptor)
