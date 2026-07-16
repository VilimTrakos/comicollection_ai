"""Fail-closed production configuration."""

from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from .passwords import ScryptParams


MAX_ACCESS_TTL_SECONDS = 60 * 60
MAX_REFRESH_TTL_SECONDS = 90 * 24 * 60 * 60
MAX_SESSION_TTL_SECONDS = 365 * 24 * 60 * 60
MAX_TENANT_STORAGE_BYTES = 10 * 1024 * 1024 * 1024
MAX_DISK_RESERVE_BYTES = 100 * 1024 * 1024 * 1024


@dataclass(frozen=True)
class ProductionConfig:
    host: str
    port: int
    auth_database: Path
    tenant_root: Path
    password_pepper: bytes
    scrypt: ScryptParams
    registration_enabled: bool
    access_ttl_ms: int
    refresh_ttl_ms: int
    session_ttl_ms: int
    tenant_storage_limit_bytes: int
    disk_reserve_bytes: int

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "ProductionConfig":
        return load_config(env)


def load_config(env: Mapping[str, str] | None = None) -> ProductionConfig:
    values = os.environ if env is None else env
    pepper = _secret(values)
    params = ScryptParams(
        n=_integer(values, "COMICOLLECT_SCRYPT_N", 32768),
        r=_integer(values, "COMICOLLECT_SCRYPT_R", 8),
        p=_integer(values, "COMICOLLECT_SCRYPT_P", 3),
        dklen=_integer(values, "COMICOLLECT_SCRYPT_DKLEN", 32),
        maxmem=_integer(
            values, "COMICOLLECT_SCRYPT_MAXMEM", 128 * 1024 * 1024
        ),
    )
    params.validate(production=True)
    port = _integer(values, "COMICOLLECT_PORT", 8787)
    if not 1 <= port <= 65535:
        raise ValueError("COMICOLLECT_PORT is invalid")
    data_root_value = values.get("COMICOLLECT_DATA_ROOT", "")
    if not data_root_value:
        raise ValueError("COMICOLLECT_DATA_ROOT is required")
    data_root = _absolute_path(data_root_value, "COMICOLLECT_DATA_ROOT")
    access = _seconds(
        values,
        "COMICOLLECT_ACCESS_TTL_SECONDS",
        900,
        maximum=MAX_ACCESS_TTL_SECONDS,
    )
    refresh = _seconds(
        values,
        "COMICOLLECT_REFRESH_TTL_SECONDS",
        30 * 86400,
        maximum=MAX_REFRESH_TTL_SECONDS,
    )
    session = _seconds(
        values,
        "COMICOLLECT_SESSION_TTL_SECONDS",
        90 * 86400,
        maximum=MAX_SESSION_TTL_SECONDS,
    )
    if not access < refresh <= session:
        raise ValueError("token lifetimes must satisfy access < refresh <= session")
    return ProductionConfig(
        host=values.get("COMICOLLECT_HOST", "127.0.0.1"),
        port=port,
        auth_database=_absolute_path(
            values.get("COMICOLLECT_AUTH_DB", str(data_root / "accounts.sqlite3")),
            "COMICOLLECT_AUTH_DB",
        ),
        tenant_root=_absolute_path(
            values.get("COMICOLLECT_TENANT_ROOT", str(data_root / "accounts")),
            "COMICOLLECT_TENANT_ROOT",
        ),
        password_pepper=pepper,
        scrypt=params,
        registration_enabled=_boolean(
            values.get("COMICOLLECT_PUBLIC_REGISTRATION", "false")
        ),
        access_ttl_ms=access * 1000,
        refresh_ttl_ms=refresh * 1000,
        session_ttl_ms=session * 1000,
        tenant_storage_limit_bytes=_bounded_bytes(
            values,
            "COMICOLLECT_TENANT_STORAGE_LIMIT_BYTES",
            512 * 1024 * 1024,
            MAX_TENANT_STORAGE_BYTES,
        ),
        disk_reserve_bytes=_bounded_bytes(
            values,
            "COMICOLLECT_DISK_RESERVE_BYTES",
            1024 * 1024 * 1024,
            MAX_DISK_RESERVE_BYTES,
        ),
    )


def _secret(values: Mapping[str, str]) -> bytes:
    inline = values.get("COMICOLLECT_PASSWORD_PEPPER", "")
    file_name = values.get("COMICOLLECT_PASSWORD_PEPPER_FILE", "")
    if bool(inline) == bool(file_name):
        raise ValueError(
            "configure exactly one COMICOLLECT_PASSWORD_PEPPER or "
            "COMICOLLECT_PASSWORD_PEPPER_FILE"
        )
    # Pepper files are binary secrets (the deployment guide creates one with
    # ``openssl rand``), so every byte is significant.  Trimming here would
    # silently change a valid key whose first or last byte happens to look like
    # ASCII whitespace.
    if inline:
        secret = inline.encode("utf-8")
    else:
        secret_path = _absolute_path(
            file_name,
            "COMICOLLECT_PASSWORD_PEPPER_FILE",
        )
        metadata = secret_path.stat()
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError("password pepper must be a regular file")
        if metadata.st_mode & 0o022:
            raise ValueError("password pepper file must not be group/world writable")
        secret = secret_path.read_bytes()
    if len(secret) < 32:
        raise ValueError("password pepper must contain at least 32 bytes")
    return secret


def _integer(values: Mapping[str, str], key: str, default: int) -> int:
    try:
        return int(values.get(key, str(default)))
    except ValueError as exc:
        raise ValueError(f"{key} must be an integer") from exc


def _absolute_path(value: str, key: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise ValueError(f"{key} must be an absolute path")
    return path


def _seconds(
    values: Mapping[str, str],
    key: str,
    default: int,
    *,
    maximum: int,
) -> int:
    value = _integer(values, key, default)
    if value <= 0:
        raise ValueError(f"{key} must be positive")
    if value > maximum:
        raise ValueError(f"{key} exceeds the safe maximum of {maximum} seconds")
    return value


def _boolean(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes"}:
        return True
    if normalized in {"0", "false", "no"}:
        return False
    raise ValueError("boolean configuration must be true or false")


def _bounded_bytes(
    values: Mapping[str, str],
    key: str,
    default: int,
    maximum: int,
) -> int:
    value = _integer(values, key, default)
    if not 0 < value <= maximum:
        raise ValueError(f"{key} must be between 1 and {maximum} bytes")
    return value
