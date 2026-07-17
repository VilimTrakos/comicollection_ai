"""Operator-only account bootstrap commands for the production backend."""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from typing import Callable, Mapping, Sequence, TextIO

from .api_errors import PublicApiError
from .auth_repository import AuthRepository
from .auth_service import AuthService
from .config import load_config
from .passwords import PasswordHasher


PasswordReader = Callable[[str], str]


def main(
    argv: Sequence[str] | None = None,
    *,
    environ: Mapping[str, str] | None = None,
    password_reader: PasswordReader | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
) -> int:
    output = stdout or sys.stdout
    errors = stderr or sys.stderr
    arguments = _parser().parse_args(argv)
    values = os.environ if environ is None else environ
    try:
        service = _service_from_environment(values)
    except (OSError, ValueError) as exc:
        print(f"Production configuration is invalid: {exc}", file=errors)
        return 1
    return create_account(
        service,
        email=arguments.email,
        display_name=arguments.display_name,
        password_reader=password_reader or getpass.getpass,
        stdout=output,
        stderr=errors,
    )


def create_account(
    service: AuthService,
    *,
    email: str,
    display_name: str,
    password_reader: PasswordReader,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    password = password_reader("New account password: ")
    confirmation = password_reader("Repeat password: ")
    if password != confirmation:
        print("Passwords do not match; no account was created.", file=stderr)
        return 2
    try:
        account = service.provision_account(
            email=email,
            password=password,
            display_name=display_name,
        )
    except PublicApiError as exc:
        print(f"Account was not created ({exc.code}): {exc}", file=stderr)
        return 1
    finally:
        password = ""
        confirmation = ""
    print(f"Account created: {account['id']}", file=stdout)
    return 0


def _service_from_environment(values: Mapping[str, str]) -> AuthService:
    config = load_config(values)
    return AuthService(
        AuthRepository(config.auth_database),
        PasswordHasher(config.password_pepper, config.scrypt),
        registration_enabled=False,
        access_ttl_ms=config.access_ttl_ms,
        refresh_ttl_ms=config.refresh_ttl_ms,
        session_ttl_ms=config.session_ttl_ms,
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m comicollect_backend.admin_cli",
        description="Comicollect production operator commands",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)
    create = subcommands.add_parser(
        "create-account",
        help="prompt securely and create one account",
    )
    create.add_argument("--email", required=True)
    create.add_argument("--display-name", required=True)
    return parser


if __name__ == "__main__":
    raise SystemExit(main())
