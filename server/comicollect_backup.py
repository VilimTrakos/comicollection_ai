#!/usr/bin/env python3
"""Production backup creation and offline restore verification CLI."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path
from typing import Sequence

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_service import AuthService
from comicollect_backend.backup import BackupManager, verify_generation
from comicollect_backend.config import ProductionConfig, load_config
from comicollect_backend.passwords import PasswordHasher


def create_backup(
    config: ProductionConfig,
    destination: Path,
    *,
    validate_auth: bool,
) -> Path | None:
    """Create a generation, optionally without opening the pre-migration DB."""

    tenant_databases = tuple(config.tenant_root.glob("account-*.sqlite3"))
    if config.auth_database.is_symlink() or not config.auth_database.is_file():
        if tenant_databases:
            raise RuntimeError("tenant databases exist without the auth database")
        if validate_auth:
            raise FileNotFoundError("production backup requires an existing auth database")
        return None
    if validate_auth:
        AuthService(
            AuthRepository(config.auth_database),
            PasswordHasher(config.password_pepper, config.scrypt),
            registration_enabled=config.registration_enabled,
            access_ttl_ms=config.access_ttl_ms,
            refresh_ttl_ms=config.refresh_ttl_ms,
            session_ttl_ms=config.session_ttl_ms,
        )
    return BackupManager(
        minimum_free_bytes=config.backup_reserve_bytes,
    ).create(
        config.auth_database,
        tenant_databases,
        destination,
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create", help="create a validated production backup")
    create.add_argument("--backup-dir", required=True, type=Path)
    snapshot = commands.add_parser(
        "snapshot-if-present",
        help="take a non-migrating pre-release snapshot when storage exists",
    )
    snapshot.add_argument("--backup-dir", required=True, type=Path)
    verify = commands.add_parser(
        "verify",
        help="fully verify a completed generation before restore",
    )
    verify.add_argument("generation", type=Path)
    args = parser.parse_args(argv)

    if args.command == "verify":
        try:
            verify_generation(args.generation)
        except (OSError, ValueError, RuntimeError, sqlite3.DatabaseError) as error:
            raise SystemExit(f"backup verification failed: {error}") from error
        print(f"Verified backup generation: {args.generation}")
        return 0

    try:
        config = load_config()
        generation = create_backup(
            config,
            args.backup_dir,
            validate_auth=args.command == "create",
        )
    except (OSError, ValueError, RuntimeError, sqlite3.DatabaseError) as error:
        raise SystemExit(f"production backup failed: {error}") from error
    if generation is None:
        print("No existing production database; pre-release backup was not required.")
    else:
        print(generation)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
