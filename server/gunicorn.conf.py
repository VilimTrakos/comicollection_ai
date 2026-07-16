"""Bounded single-node runtime for the SQLite closed beta."""

from __future__ import annotations

import os


def _integer(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as error:
        raise RuntimeError(f"{name} must be an integer") from error
    if not minimum <= value <= maximum:
        raise RuntimeError(f"{name} must be between {minimum} and {maximum}")
    return value


# One process is intentional: SQLite tenant stores and the bounded auth rate
# limiter are process-local.  Horizontal scaling requires PostgreSQL and a
# shared limiter before this value may change.
workers = 1
worker_class = "gthread"
threads = _integer("COMICOLLECT_GUNICORN_THREADS", 4, 2, 4)

bind = "127.0.0.1:" + str(_integer("COMICOLLECT_PORT", 8787, 1, 65535))
backlog = 128
timeout = _integer("COMICOLLECT_REQUEST_TIMEOUT_SECONDS", 30, 10, 60)
graceful_timeout = 30
keepalive = 5

limit_request_line = 4094
limit_request_fields = 50
limit_request_field_size = 8190
max_requests = 10_000
max_requests_jitter = 1_000

wsgi_app = "comicollect_wsgi:create_application()"
preload_app = False
forwarded_allow_ips = "127.0.0.1,::1"
secure_scheme_headers = {"X-FORWARDED-PROTO": "https"}

accesslog = "-"
errorlog = "-"
capture_output = True
loglevel = os.getenv("LOG_LEVEL", "info").lower()
access_log_format = (
    '%(h)s "%(m)s %(U)s %(H)s" %(s)s %(B)s %(D)s '
    '"%({x-request-id}i)s"'
)
worker_tmp_dir = "/run/comicollect"
umask = 0o077
