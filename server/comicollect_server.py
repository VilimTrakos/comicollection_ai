#!/usr/bin/env python3
"""Comicollect LAN sync server. Python standard library only."""
from __future__ import annotations

import argparse
import hmac
import json
import logging
import os
import shutil
import sqlite3
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

LOG = logging.getLogger("comicollect")
MAX_BODY = 8 * 1024 * 1024
FIELDS = (
    "id", "series", "edition", "number", "title", "publisher", "year",
    "owned", "is_read", "condition_grade", "purchase_price", "estimated_value",
    "is_duplicate", "loaned_to", "notes", "deleted", "updated_at",
)
UPSERT = f"""INSERT INTO comics ({','.join(FIELDS)}) VALUES ({','.join('?' for _ in FIELDS)})
ON CONFLICT(id) DO UPDATE SET {','.join(f'{f}=excluded.{f}' for f in FIELDS[1:])}
WHERE excluded.updated_at > comics.updated_at"""


class Store:
    def __init__(self, path: Path):
        self.path = path
        self.lock = Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=NORMAL")
        db.execute("PRAGMA busy_timeout=15000")
        return db

    def _initialize(self) -> None:
        with self.connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS comics(
                id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
                number INTEGER NOT NULL, title TEXT NOT NULL, publisher TEXT NOT NULL DEFAULT '',
                year INTEGER, owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
                condition_grade TEXT NOT NULL, purchase_price REAL, estimated_value REAL,
                is_duplicate INTEGER NOT NULL, loaned_to TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '', deleted INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL)""")
            db.execute("CREATE INDEX IF NOT EXISTS idx_updated ON comics(updated_at)")
            db.execute("CREATE INDEX IF NOT EXISTS idx_series ON comics(series, edition, number)")

    def sync(self, since: int, changes: list[dict]) -> tuple[int, list[dict]]:
        server_time = int(time.time() * 1000)
        with self.lock, self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            for item in changes:
                clean = validate_comic(item)
                db.execute(UPSERT, [clean[f] for f in FIELDS])
            rows = db.execute(
                "SELECT * FROM comics WHERE updated_at > ? ORDER BY updated_at", (since,)
            ).fetchall()
            db.commit()
        return server_time, [dict(row) for row in rows]

    def stats(self) -> dict:
        with self.connect() as db:
            row = db.execute("SELECT COUNT(*) total, SUM(CASE WHEN deleted=0 THEN 1 ELSE 0 END) active FROM comics").fetchone()
        return {"records": row["total"], "active": row["active"] or 0}

    def backup(self, destination: Path) -> Path:
        destination.mkdir(parents=True, exist_ok=True)
        target = destination / time.strftime("comicollect-%Y%m%d-%H%M%S.sqlite3")
        with self.lock, self.connect() as source, sqlite3.connect(target) as dest:
            source.backup(dest)
        backups = sorted(destination.glob("comicollect-*.sqlite3"), reverse=True)
        for stale in backups[14:]:
            stale.unlink()
        return target


def validate_comic(raw: dict) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("change must be an object")
    required = ("id", "series", "edition", "number", "title", "updated_at")
    if any(key not in raw for key in required):
        raise ValueError("comic is missing required fields")
    text = lambda key, limit: str(raw.get(key, ""))[:limit]
    comic = {
        "id": text("id", 64), "series": text("series", 200), "edition": text("edition", 200),
        "number": int(raw["number"]), "title": text("title", 500), "publisher": text("publisher", 200),
        "year": int(raw["year"]) if raw.get("year") is not None else None,
        "owned": int(bool(raw.get("owned"))), "is_read": int(bool(raw.get("is_read"))),
        "condition_grade": text("condition_grade", 8) or "F",
        "purchase_price": float(raw["purchase_price"]) if raw.get("purchase_price") is not None else None,
        "estimated_value": float(raw["estimated_value"]) if raw.get("estimated_value") is not None else None,
        "is_duplicate": int(bool(raw.get("is_duplicate"))), "loaned_to": text("loaned_to", 300),
        "notes": text("notes", 10000), "deleted": int(bool(raw.get("deleted"))),
        "updated_at": int(raw["updated_at"]),
    }
    if not comic["id"] or not comic["series"] or comic["number"] < 0:
        raise ValueError("invalid id, series, or number")
    if comic["condition_grade"] not in {"M", "VF", "F", "G", "P"}:
        raise ValueError("invalid condition_grade")
    return comic


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "Comicollect/1.0"

    def log_message(self, fmt: str, *args) -> None:
        LOG.info("%s %s", self.address_string(), fmt % args)

    def json_response(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def authorized(self) -> bool:
        supplied = self.headers.get("Authorization", "").removeprefix("Bearer ")
        return bool(supplied) and hmac.compare_digest(supplied, self.server.api_token)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.json_response(HTTPStatus.OK, {"ok": True, "version": 1, **self.server.store.stats()})
        else:
            self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/api/v1/sync":
            return self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})
        if not self.authorized():
            return self.json_response(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY:
                raise ValueError("invalid body size")
            payload = json.loads(self.rfile.read(length))
            since = max(0, int(payload.get("since", 0)))
            changes = payload.get("changes", [])
            if not isinstance(changes, list) or len(changes) > 10000:
                raise ValueError("invalid changes")
            server_time, remote = self.server.store.sync(since, changes)
            self.json_response(HTTPStatus.OK, {"server_time": server_time, "changes": remote})
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            self.json_response(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception:
            LOG.exception("sync failed")
            self.json_response(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal error"})


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def __init__(self, address, store: Store, api_token: str):
        super().__init__(address, ApiHandler)
        self.store, self.api_token = store, api_token


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.getenv("COMICOLLECT_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.getenv("COMICOLLECT_PORT", "8787")))
    parser.add_argument("--db", type=Path, default=Path(os.getenv("COMICOLLECT_DB", "./data/comicollect.sqlite3")))
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--backup-dir", type=Path, default=Path(os.getenv("COMICOLLECT_BACKUP_DIR", "./backups")))
    args = parser.parse_args()
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
    store = Store(args.db)
    if args.backup:
        print(store.backup(args.backup_dir))
        return
    token = os.getenv("COMICOLLECT_TOKEN", "")
    if len(token) < 32:
        raise SystemExit("COMICOLLECT_TOKEN must contain at least 32 characters")
    LOG.info("listening on %s:%s; database=%s", args.host, args.port, args.db)
    Server((args.host, args.port), store, token).serve_forever()


if __name__ == "__main__":
    main()
