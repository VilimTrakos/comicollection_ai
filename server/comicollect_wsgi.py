"""Gunicorn application factory for the authenticated backend."""

from __future__ import annotations

import argparse
import os
from typing import Mapping, Sequence

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_service import AuthService
from comicollect_backend.config import load_config
from comicollect_backend.passwords import PasswordHasher
from comicollect_backend.production_api import ProductionApi
from comicollect_backend.tenant_store import TenantStore
from comicollect_backend.wsgi import WsgiApplication


def create_application(
    env: Mapping[str, str] | None = None,
) -> WsgiApplication:
    """Build dependencies lazily and fail worker startup on invalid config."""

    values = os.environ if env is None else env
    config = load_config(values)
    repository = AuthRepository(config.auth_database)
    auth = AuthService(
        repository,
        PasswordHasher(config.password_pepper, config.scrypt),
        registration_enabled=config.registration_enabled,
        access_ttl_ms=config.access_ttl_ms,
        refresh_ttl_ms=config.refresh_ttl_ms,
        session_ttl_ms=config.session_ttl_ms,
    )
    api = ProductionApi(
        auth,
        TenantStore(
            config.tenant_root,
            maximum_tenant_bytes=config.tenant_storage_limit_bytes,
            minimum_free_bytes=config.disk_reserve_bytes,
        ),
    )
    return WsgiApplication(
        api,
        trusted_proxy_addresses=_trusted_proxies(values),
    )


def _trusted_proxies(values: Mapping[str, str]) -> tuple[str, ...]:
    raw = values.get(
        "COMICOLLECT_TRUSTED_PROXY_ADDRESSES",
        "127.0.0.1,::1",
    )
    return tuple(value.strip() for value in raw.split(",") if value.strip())


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate configuration and initialize storage, then exit",
    )
    args = parser.parse_args(argv)
    if not args.check:
        parser.error("use Gunicorn to serve this module; only --check is supported")
    create_application()
    print("Comicollect production configuration and storage are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
