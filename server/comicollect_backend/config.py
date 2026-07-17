"""Fail-closed production configuration."""

from __future__ import annotations

import os
import stat
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping

from .passwords import ScryptParams


MAX_ACCESS_TTL_SECONDS = 60 * 60
MAX_REFRESH_TTL_SECONDS = 90 * 24 * 60 * 60
MAX_SESSION_TTL_SECONDS = 365 * 24 * 60 * 60
MAX_TENANT_STORAGE_BYTES = 10 * 1024 * 1024 * 1024
MAX_DISK_RESERVE_BYTES = 100 * 1024 * 1024 * 1024
MAX_BACKUP_RESERVE_BYTES = 100 * 1024 * 1024 * 1024
MAX_SMTP_TIMEOUT_SECONDS = 30


@dataclass(frozen=True)
class EmailDeliveryConfig:
    """Validated adapter settings; the password is deliberately repr-safe."""

    transport: str
    host: str
    port: int
    security: str
    username: str | None
    password: str | None = field(repr=False)
    from_address: str
    from_name: str
    timeout_seconds: int


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
    backup_reserve_bytes: int
    email_delivery: EmailDeliveryConfig

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
    registration_enabled = _boolean(
        values.get("COMICOLLECT_PUBLIC_REGISTRATION", "false")
    )
    email_delivery = _email_delivery(values)
    if registration_enabled and email_delivery.transport == "disabled":
        raise ValueError(
            "public registration requires configured email delivery"
        )
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
        registration_enabled=registration_enabled,
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
        backup_reserve_bytes=_bounded_bytes(
            values,
            "COMICOLLECT_BACKUP_RESERVE_BYTES",
            1024 * 1024 * 1024,
            MAX_BACKUP_RESERVE_BYTES,
        ),
        email_delivery=email_delivery,
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
        if secret_path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
            raise ValueError("password pepper must be a regular file")
        # The long-lived service may only read this root-controlled secret.
        # Owner-writable files are rejected too, otherwise a custom path owned
        # by the service account would let a compromised process replace the
        # pepper and permanently break password verification.
        forbidden = (
            stat.S_IWUSR
            | stat.S_IXUSR
            | stat.S_IWGRP
            | stat.S_IXGRP
            | stat.S_IRWXO
        )
        if metadata.st_mode & forbidden:
            raise ValueError(
                "password pepper file must be read-only, non-executable, and "
                "not world accessible"
            )
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


def _email_delivery(values: Mapping[str, str]) -> EmailDeliveryConfig:
    transport = values.get("COMICOLLECT_EMAIL_TRANSPORT", "disabled").strip().lower()
    smtp_keys = (
        "COMICOLLECT_SMTP_HOST",
        "COMICOLLECT_SMTP_PORT",
        "COMICOLLECT_SMTP_SECURITY",
        "COMICOLLECT_SMTP_USERNAME",
        "COMICOLLECT_SMTP_PASSWORD",
        "COMICOLLECT_SMTP_PASSWORD_FILE",
        "COMICOLLECT_SMTP_TIMEOUT_SECONDS",
        "COMICOLLECT_EMAIL_FROM_ADDRESS",
        "COMICOLLECT_EMAIL_FROM_NAME",
    )
    if transport == "disabled":
        if any(values.get(key, "") for key in smtp_keys):
            raise ValueError("SMTP settings require COMICOLLECT_EMAIL_TRANSPORT=smtp")
        return EmailDeliveryConfig(
            transport="disabled",
            host="",
            port=0,
            security="",
            username=None,
            password=None,
            from_address="",
            from_name="",
            timeout_seconds=0,
        )
    if transport != "smtp":
        raise ValueError("COMICOLLECT_EMAIL_TRANSPORT must be disabled or smtp")

    security = values.get("COMICOLLECT_SMTP_SECURITY", "starttls").strip().lower()
    if security not in {"starttls", "implicit_tls"}:
        raise ValueError(
            "COMICOLLECT_SMTP_SECURITY must be starttls or implicit_tls"
        )
    host = values.get("COMICOLLECT_SMTP_HOST", "").strip()
    if (
        not host
        or len(host) > 253
        or any(
            character.isspace() or ord(character) < 32 or ord(character) == 127
            for character in host
        )
    ):
        raise ValueError("COMICOLLECT_SMTP_HOST is invalid")
    port = _integer(
        values,
        "COMICOLLECT_SMTP_PORT",
        465 if security == "implicit_tls" else 587,
    )
    if not 1 <= port <= 65535:
        raise ValueError("COMICOLLECT_SMTP_PORT is invalid")
    timeout = _integer(values, "COMICOLLECT_SMTP_TIMEOUT_SECONDS", 10)
    if not 1 <= timeout <= MAX_SMTP_TIMEOUT_SECONDS:
        raise ValueError(
            "COMICOLLECT_SMTP_TIMEOUT_SECONDS must be between 1 and "
            f"{MAX_SMTP_TIMEOUT_SECONDS}"
        )

    from_address = _configured_mailbox(
        values.get("COMICOLLECT_EMAIL_FROM_ADDRESS", ""),
        "COMICOLLECT_EMAIL_FROM_ADDRESS",
    )
    from_name = values.get("COMICOLLECT_EMAIL_FROM_NAME", "Comicollect").strip()
    if (
        not from_name
        or len(from_name) > 100
        or any(
            ord(character) < 32 or ord(character) == 127
            for character in from_name
        )
    ):
        raise ValueError("COMICOLLECT_EMAIL_FROM_NAME is invalid")

    raw_username = values.get("COMICOLLECT_SMTP_USERNAME", "")
    username = raw_username.strip() or None
    if username is not None and (
        username != raw_username
        or len(username) > 512
        or any(
            ord(character) < 32 or ord(character) == 127
            for character in username
        )
    ):
        raise ValueError("COMICOLLECT_SMTP_USERNAME is invalid")
    password = _smtp_password(values)
    if (username is None) != (password is None):
        raise ValueError("SMTP username and password must be configured together")

    return EmailDeliveryConfig(
        transport="smtp",
        host=host,
        port=port,
        security=security,
        username=username,
        password=password,
        from_address=from_address,
        from_name=from_name,
        timeout_seconds=timeout,
    )


def _smtp_password(values: Mapping[str, str]) -> str | None:
    inline = values.get("COMICOLLECT_SMTP_PASSWORD", "")
    file_name = values.get("COMICOLLECT_SMTP_PASSWORD_FILE", "")
    if inline and file_name:
        raise ValueError(
            "configure at most one COMICOLLECT_SMTP_PASSWORD or "
            "COMICOLLECT_SMTP_PASSWORD_FILE"
        )
    if not inline and not file_name:
        return None
    if inline:
        secret = inline
    else:
        path = _absolute_path(file_name, "COMICOLLECT_SMTP_PASSWORD_FILE")
        metadata = path.stat()
        if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
            raise ValueError("SMTP password must be a regular file")
        forbidden = (
            stat.S_IWUSR
            | stat.S_IXUSR
            | stat.S_IWGRP
            | stat.S_IXGRP
            | stat.S_IRWXO
        )
        if metadata.st_mode & forbidden:
            raise ValueError(
                "SMTP password file must be read-only, non-executable, and "
                "not world accessible"
            )
        try:
            secret = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            raise ValueError("SMTP password file must contain UTF-8 text") from error
    if not secret or "\0" in secret or len(secret.encode("utf-8")) > 4096:
        raise ValueError("SMTP password is invalid")
    return secret


def _configured_mailbox(value: str, key: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value.encode("utf-8")) > 254
        or value.count("@") != 1
        or not all(value.split("@", 1))
        or any(
            character.isspace() or ord(character) < 32 or ord(character) == 127
            for character in value
        )
    ):
        raise ValueError(f"{key} is invalid")
    return value
