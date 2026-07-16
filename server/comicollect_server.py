#!/usr/bin/env python3
"""Comicollect LAN sync server. Python standard library only."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import logging
import math
import os
import re
import shutil
import sqlite3
import time
import uuid
from contextlib import closing
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

LOG = logging.getLogger("comicollect")
MAX_BODY = 8 * 1024 * 1024
MAX_V2_MUTATIONS = 100
MAX_V2_CHANGES_PER_MUTATION = 500
MAX_V2_TOTAL_CHANGES = 500
MAX_V2_LIMIT = 100
MAX_V2_RESPONSE_BYTES = 6 * 1024 * 1024
MAX_V2_GROUP_BYTES = 5 * 1024 * 1024
MAX_V2_REQUEST_CACHE = 1000
MAX_V2_REQUEST_CACHE_BYTES = 32 * 1024 * 1024
V2_REQUEST_CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000
V2_ENTITY_TYPES = {
    "custom_issue",
    "collection_entry",
    "copy",
    "barcode_mapping",
}
V2_OPERATIONS = {"upsert", "delete"}
CONDITION_GRADES = {"", "M", "VF", "F", "G", "P"}
IDENTIFIER_RE = re.compile(r"^[^\x00-\x1f\x7f]+$")
FIELDS = (
    "id", "series", "edition", "number", "title", "publisher", "year",
    "owned", "is_read", "condition_grade", "purchase_price", "estimated_value",
    "is_duplicate", "loaned_to", "notes", "cover_asset", "rating", "page_count",
    "writer", "artist", "deleted", "updated_at",
)
UPSERT = f"""INSERT INTO comics ({','.join(FIELDS)}) VALUES ({','.join('?' for _ in FIELDS)})
ON CONFLICT(id) DO UPDATE SET {','.join(f'{f}=excluded.{f}' for f in FIELDS[1:])}
WHERE excluded.updated_at > comics.updated_at"""


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code

    def payload(self) -> dict:
        return {"error": str(self), "code": self.code}


class V1WriteConflict(ApiError):
    def __init__(self):
        super().__init__(
            HTTPStatus.CONFLICT,
            "v1_read_only",
            "v1 writes are disabled after sync v2 activation",
        )


class Store:
    def __init__(self, path: Path):
        self.path = path
        self.lock = Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA synchronous=FULL")
        db.execute("PRAGMA busy_timeout=15000")
        return db

    def _initialize(self) -> None:
        with closing(self.connect()) as db, db:
            # WAL mode persists in the database. Reapplying it on every sync
            # connection can take an unnecessary schema lock under load.
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""CREATE TABLE IF NOT EXISTS comics(
                id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
                number INTEGER NOT NULL, title TEXT NOT NULL, publisher TEXT NOT NULL DEFAULT '',
                year INTEGER, owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
                condition_grade TEXT NOT NULL, purchase_price REAL, estimated_value REAL,
                is_duplicate INTEGER NOT NULL, loaned_to TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '', cover_asset TEXT NOT NULL DEFAULT '',
                rating INTEGER NOT NULL DEFAULT 0, page_count INTEGER,
                writer TEXT NOT NULL DEFAULT '', artist TEXT NOT NULL DEFAULT '',
                deleted INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL)""")
            columns = {row[1] for row in db.execute("PRAGMA table_info(comics)")}
            if "cover_asset" not in columns:
                db.execute(
                    "ALTER TABLE comics ADD COLUMN cover_asset TEXT NOT NULL DEFAULT ''"
                )
            if "rating" not in columns:
                db.execute(
                    "ALTER TABLE comics ADD COLUMN rating INTEGER NOT NULL DEFAULT 0"
                )
            if "page_count" not in columns:
                db.execute("ALTER TABLE comics ADD COLUMN page_count INTEGER")
            if "writer" not in columns:
                db.execute(
                    "ALTER TABLE comics ADD COLUMN writer TEXT NOT NULL DEFAULT ''"
                )
            if "artist" not in columns:
                db.execute(
                    "ALTER TABLE comics ADD COLUMN artist TEXT NOT NULL DEFAULT ''"
                )
            db.execute("CREATE INDEX IF NOT EXISTS idx_updated ON comics(updated_at)")
            db.execute("CREATE INDEX IF NOT EXISTS idx_series ON comics(series, edition, number)")

            db.execute("""CREATE TABLE IF NOT EXISTS sync_meta(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS v2_entities(
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                issue_id TEXT NOT NULL DEFAULT '',
                operation TEXT NOT NULL,
                data_json TEXT NOT NULL,
                revision INTEGER NOT NULL,
                PRIMARY KEY(entity_type, entity_id)
            )""")
            entity_columns = {
                row[1] for row in db.execute("PRAGMA table_info(v2_entities)")
            }
            if "issue_id" not in entity_columns:
                db.execute(
                    "ALTER TABLE v2_entities "
                    "ADD COLUMN issue_id TEXT NOT NULL DEFAULT ''"
                )
            self._backfill_entity_issue_ids(db)
            db.execute("""CREATE TABLE IF NOT EXISTS v2_change_groups(
                revision INTEGER PRIMARY KEY AUTOINCREMENT,
                mutation_id TEXT NOT NULL UNIQUE,
                changes_json TEXT NOT NULL,
                committed_at INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS v2_mutations(
                mutation_id TEXT PRIMARY KEY,
                payload_hash TEXT NOT NULL,
                revision INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                device_id TEXT NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS v2_requests(
                request_id TEXT PRIMARY KEY,
                payload_hash TEXT NOT NULL,
                response_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                device_id TEXT NOT NULL
            )""")
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_v2_entities_revision "
                "ON v2_entities(revision)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_v2_entities_issue "
                "ON v2_entities(entity_type,issue_id)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_v2_mutations_created "
                "ON v2_mutations(created_at)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_v2_requests_created "
                "ON v2_requests(created_at)"
            )
            db.execute(
                "INSERT OR IGNORE INTO sync_meta(key,value) VALUES('server_id',?)",
                (str(uuid.uuid4()),),
            )
            db.execute(
                "INSERT OR IGNORE INTO sync_meta(key,value) VALUES('v2_activated','0')"
            )
            if self._meta(db, "v2_bootstrapped") != "1":
                self._bootstrap_v1(db)
                self._set_meta(db, "v2_bootstrapped", "1")

    @staticmethod
    def _meta(db: sqlite3.Connection, key: str) -> str | None:
        row = db.execute("SELECT value FROM sync_meta WHERE key=?", (key,)).fetchone()
        return None if row is None else str(row[0])

    @staticmethod
    def _set_meta(db: sqlite3.Connection, key: str, value: str) -> None:
        db.execute(
            "INSERT INTO sync_meta(key,value) VALUES(?,?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, value),
        )

    @staticmethod
    def _backfill_entity_issue_ids(db: sqlite3.Connection) -> None:
        rows = db.execute(
            "SELECT entity_type,entity_id,data_json FROM v2_entities "
            "WHERE issue_id=''"
        ).fetchall()
        for row in rows:
            try:
                data = json.loads(row["data_json"])
            except (TypeError, json.JSONDecodeError) as exc:
                raise RuntimeError("invalid stored v2 entity payload") from exc
            issue_id = (
                row["entity_id"]
                if row["entity_type"] == "custom_issue"
                else data.get("issue_id")
            )
            if not isinstance(issue_id, str) or not issue_id:
                raise RuntimeError("stored v2 entity has no issue_id")
            db.execute(
                "UPDATE v2_entities SET issue_id=? "
                "WHERE entity_type=? AND entity_id=?",
                (issue_id, row["entity_type"], row["entity_id"]),
            )

    @property
    def server_id(self) -> str:
        with closing(self.connect()) as db:
            value = self._meta(db, "server_id")
        if value is None:  # Defensive: initialization always creates it.
            raise RuntimeError("sync server id is missing")
        return value

    def _bootstrap_v1(self, db: sqlite3.Connection) -> None:
        rows = db.execute("SELECT * FROM comics ORDER BY id").fetchall()
        for row in rows:
            clean = validate_comic(dict(row))
            mutation_id = "bootstrap:" + _payload_hash(clean)
            self._record_internal_group(
                db,
                mutation_id,
                _v1_changes(clean),
                project_v1=False,
            )

    def sync(self, since: int, changes: list[dict]) -> tuple[int, list[dict]]:
        with self.lock, closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            clean_changes = [validate_comic(item) for item in changes]
            v2_active = self._meta(db, "v2_activated") == "1"
            if clean_changes and v2_active:
                # A client may be retrying a v1 request whose HTTP response
                # was lost immediately before another device activated v2.
                # Exact/already-older writes are safe no-ops and let that
                # client durably finish its cutover. Any write which could
                # still alter the flattened projection remains forbidden.
                for clean in clean_changes:
                    current = db.execute(
                        "SELECT updated_at FROM comics WHERE id=?",
                        (clean["id"],),
                    ).fetchone()
                    if current is None or clean["updated_at"] > current[0]:
                        raise V1WriteConflict()
            for clean in clean_changes:
                if v2_active:
                    continue
                current = db.execute(
                    "SELECT updated_at FROM comics WHERE id=?", (clean["id"],)
                ).fetchone()
                accepted = current is None or clean["updated_at"] > current[0]
                if accepted:
                    db.execute(UPSERT, [clean[f] for f in FIELDS])
                    self._record_internal_group(
                        db,
                        "v1:" + _payload_hash(clean),
                        _v1_changes(clean),
                        project_v1=False,
                    )
            rows = db.execute(
                "SELECT * FROM comics WHERE updated_at > ? ORDER BY updated_at", (since,)
            ).fetchall()
            latest = db.execute(
                "SELECT COALESCE(MAX(updated_at),0) FROM comics"
            ).fetchone()[0]
            server_time = max(int(time.time() * 1000), int(latest))
            db.commit()
        return server_time, [dict(row) for row in rows]

    def sync_v2(self, payload: dict) -> dict:
        request = validate_v2_request(payload)
        supplied_server_id = request.get("server_id", "")
        request_hash = _payload_hash(request)
        with self.lock, closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            server_id = self._meta(db, "server_id")
            if supplied_server_id and supplied_server_id != server_id:
                raise ApiError(
                    HTTPStatus.CONFLICT,
                    "server_mismatch",
                    "server_id does not match this server",
                )

            cached = db.execute(
                "SELECT payload_hash,response_json FROM v2_requests "
                "WHERE request_id=?",
                (request["request_id"],),
            ).fetchone()
            if cached is not None:
                if not hmac.compare_digest(cached["payload_hash"], request_hash):
                    raise ApiError(
                        HTTPStatus.CONFLICT,
                        "request_id_reused",
                        "request_id was already used for a different request",
                    )
                db.commit()
                return json.loads(cached["response_json"])

            high_before = db.execute(
                "SELECT COALESCE(MAX(revision),0) FROM v2_change_groups"
            ).fetchone()[0]
            if request["cursor"] > high_before:
                raise ApiError(
                    HTTPStatus.CONFLICT,
                    "cursor_invalid",
                    "cursor is ahead of this server",
                )

            receipts: dict[str, sqlite3.Row] = {}
            for mutation in request["mutations"]:
                receipt = db.execute(
                    "SELECT payload_hash,revision FROM v2_mutations "
                    "WHERE mutation_id=?",
                    (mutation["mutation_id"],),
                ).fetchone()
                if receipt is not None:
                    mutation_hash = _payload_hash(mutation)
                    if not hmac.compare_digest(receipt["payload_hash"], mutation_hash):
                        raise ApiError(
                            HTTPStatus.CONFLICT,
                            "mutation_id_reused",
                            "mutation_id was already used for different changes",
                    )
                    receipts[mutation["mutation_id"]] = receipt
                    continue

                # Bootstrap and legacy-v1 bridge groups intentionally share
                # the global mutation-id namespace. A caller must never turn
                # an internal historical group into a server error by reusing
                # its id, even though it has no client receipt row.
                internal_group = db.execute(
                    "SELECT 1 FROM v2_change_groups WHERE mutation_id=?",
                    (mutation["mutation_id"],),
                ).fetchone()
                if internal_group is not None:
                    raise ApiError(
                        HTTPStatus.CONFLICT,
                        "mutation_id_reused",
                        "mutation_id is already reserved by server history",
                    )

            acknowledgements = []
            for mutation in request["mutations"]:
                mutation_id = mutation["mutation_id"]
                receipt = receipts.get(mutation_id)
                if receipt is not None:
                    acknowledgements.append(
                        {
                            "mutation_id": mutation_id,
                            "revision": receipt["revision"],
                            "status": "duplicate",
                        }
                    )
                    continue
                canonical_changes = self._canonicalize_group(db, mutation["changes"])
                revision = self._record_group(
                    db,
                    mutation_id,
                    canonical_changes,
                    project_v1=True,
                )
                db.execute(
                    "INSERT INTO v2_mutations"
                    "(mutation_id,payload_hash,revision,created_at,device_id) "
                    "VALUES(?,?,?,?,?)",
                    (
                        mutation_id,
                        _payload_hash(mutation),
                        revision,
                        int(time.time() * 1000),
                        request["device_id"],
                    ),
                )
                acknowledgements.append(
                    {
                        "mutation_id": mutation_id,
                        "revision": revision,
                        "status": "applied",
                    }
                )

            if request["mutations"]:
                self._set_meta(db, "v2_activated", "1")
            high_water = db.execute(
                "SELECT COALESCE(MAX(revision),0) FROM v2_change_groups"
            ).fetchone()[0]
            rows = db.execute(
                "SELECT revision,mutation_id,changes_json "
                "FROM v2_change_groups WHERE revision>? AND revision<=? "
                "ORDER BY revision LIMIT ?",
                (request["cursor"], high_water, request["limit"] + 1),
            ).fetchall()
            server_time = int(time.time() * 1000)
            base_response = {
                "protocol": 2,
                "server_id": server_id,
                "request_id": request["request_id"],
                "server_time": server_time,
                "next_cursor": request["cursor"],
                "has_more": False,
                "acknowledgements": acknowledgements,
                "change_groups": [],
            }
            page = []
            for row in rows[: request["limit"]]:
                group = {
                    "revision": row["revision"],
                    "mutation_id": row["mutation_id"],
                    "changes": json.loads(row["changes_json"]),
                }
                candidate = page + [group]
                probe = {
                    **base_response,
                    "next_cursor": row["revision"],
                    "has_more": True,
                    "change_groups": candidate,
                }
                if len(_canonical_json(probe).encode("utf-8")) > MAX_V2_RESPONSE_BYTES:
                    break
                page = candidate
            if rows and not page:
                raise ApiError(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    "change_group_too_large",
                    "one stored change group exceeds the response limit",
                )
            consumed = len(page)
            has_more = consumed < len(rows) or len(rows) > request["limit"]
            next_cursor = page[-1]["revision"] if has_more else high_water
            response = {
                **base_response,
                "next_cursor": next_cursor,
                "has_more": has_more,
                "change_groups": page,
            }
            response_json = _canonical_json(response)
            db.execute(
                "INSERT INTO v2_requests"
                "(request_id,payload_hash,response_json,created_at,device_id) "
                "VALUES(?,?,?,?,?)",
                (
                    request["request_id"],
                    request_hash,
                    response_json,
                    int(time.time() * 1000),
                    request["device_id"],
                ),
            )
            self._prune_request_cache(db)
            db.commit()
        return response

    @staticmethod
    def _prune_request_cache(db: sqlite3.Connection) -> None:
        cutoff = int(time.time() * 1000) - V2_REQUEST_CACHE_TTL_MS
        db.execute("DELETE FROM v2_requests WHERE created_at<?", (cutoff,))
        db.execute(
            "DELETE FROM v2_requests WHERE rowid IN ("
            "SELECT rowid FROM v2_requests ORDER BY created_at DESC,rowid DESC "
            "LIMIT -1 OFFSET ?)",
            (MAX_V2_REQUEST_CACHE,),
        )
        total = int(
            db.execute(
                "SELECT COALESCE(SUM("
                "LENGTH(CAST(response_json AS BLOB))+"
                "LENGTH(CAST(payload_hash AS BLOB))+"
                "LENGTH(CAST(request_id AS BLOB))),0) FROM v2_requests"
            ).fetchone()[0]
        )
        while total > MAX_V2_REQUEST_CACHE_BYTES:
            stale = db.execute(
                "SELECT rowid,(LENGTH(CAST(response_json AS BLOB))+"
                "LENGTH(CAST(payload_hash AS BLOB))+"
                "LENGTH(CAST(request_id AS BLOB))) AS bytes "
                "FROM v2_requests ORDER BY created_at,rowid LIMIT 100"
            ).fetchall()
            if not stale:
                break
            remove = []
            removed_bytes = 0
            for row in stale:
                remove.append((row["rowid"],))
                removed_bytes += int(row["bytes"])
                if total - removed_bytes <= MAX_V2_REQUEST_CACHE_BYTES:
                    break
            db.executemany(
                "DELETE FROM v2_requests WHERE rowid=?",
                remove,
            )
            total -= removed_bytes

    def _record_internal_group(
        self,
        db: sqlite3.Connection,
        mutation_id: str,
        changes: list[dict],
        *,
        project_v1: bool,
    ) -> int:
        existing = db.execute(
            "SELECT revision FROM v2_change_groups WHERE mutation_id=?",
            (mutation_id,),
        ).fetchone()
        if existing is not None:
            return int(existing["revision"])
        canonical = self._canonicalize_group(db, changes)
        return self._record_group(
            db, mutation_id, canonical, project_v1=project_v1
        )

    def _record_group(
        self,
        db: sqlite3.Connection,
        mutation_id: str,
        canonical_changes: list[dict],
        *,
        project_v1: bool,
    ) -> int:
        encoded_changes = _canonical_json(canonical_changes)
        if len(encoded_changes.encode("utf-8")) > MAX_V2_GROUP_BYTES:
            raise ApiError(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                "mutation_too_large",
                "one mutation produces an oversized change group",
            )
        cursor = db.execute(
            "INSERT INTO v2_change_groups(mutation_id,changes_json,committed_at) "
            "VALUES(?,?,?)",
            (mutation_id, "[]", int(time.time() * 1000)),
        )
        revision = int(cursor.lastrowid)
        affected = set()
        for change in canonical_changes:
            db.execute(
                "INSERT INTO v2_entities"
                "(entity_type,entity_id,issue_id,operation,data_json,revision) "
                "VALUES(?,?,?,?,?,?) "
                "ON CONFLICT(entity_type,entity_id) DO UPDATE SET "
                "issue_id=excluded.issue_id,operation=excluded.operation,"
                "data_json=excluded.data_json,revision=excluded.revision",
                (
                    change["entity_type"],
                    change["entity_id"],
                    _change_issue_id(change),
                    change["operation"],
                    _canonical_json(change["data"]),
                    revision,
                ),
            )
            issue_id = _change_issue_id(change)
            if issue_id:
                affected.add(issue_id)
        db.execute(
            "UPDATE v2_change_groups SET changes_json=? WHERE revision=?",
            (encoded_changes, revision),
        )
        if project_v1:
            for issue_id in sorted(affected):
                self._refresh_v1_projection(db, issue_id)
        return revision

    def _canonicalize_group(
        self, db: sqlite3.Connection, changes: list[dict]
    ) -> list[dict]:
        # Explicit custom issues are authoritative. Bundled issue hints remain
        # attached to state/copy/barcode snapshots and are never promoted to a
        # custom issue; clients use them only when their local catalog is older.
        canonical: list[dict] = []
        explicit_issue_ids = {
            change["entity_id"]
            for change in changes
            if change["entity_type"] == "custom_issue"
        }
        for change in changes:
            if change["entity_type"] == "custom_issue":
                canonical.append(_canonical_change(change))
        for change in changes:
            if change["entity_type"] == "custom_issue":
                continue
            issue_id = str(change["data"]["issue_id"])
            if change["entity_type"] == "copy":
                existing_copy = self._entity(db, "copy", change["entity_id"])
                if (
                    existing_copy is not None
                    and existing_copy["data"].get("issue_id") != issue_id
                ):
                    raise ValueError("an existing copy cannot move to another issue_id")
            issue_exists = issue_id in explicit_issue_ids or self._entity(
                db, "custom_issue", issue_id
            ) is not None
            hint = change["data"].get("issue_hint")
            if not issue_exists and hint is None:
                raise ValueError(
                    f"unknown issue_id {issue_id}; issue_hint is required"
                )
            canonical.append(_canonical_change(change))
        canonical = self._normalize_copy_authority(db, canonical)
        # The same entity twice in one atomic group would make ordering inside
        # the group observable but has only one revision. Reject it explicitly.
        keys = [(item["entity_type"], item["entity_id"]) for item in canonical]
        if len(keys) != len(set(keys)):
            raise ValueError("a mutation may change an entity only once")
        return canonical

    def _normalize_copy_authority(
        self, db: sqlite3.Connection, canonical: list[dict]
    ) -> list[dict]:
        affected = {
            _change_issue_id(change)
            for change in canonical
            if change["entity_type"] in {"collection_entry", "copy"}
        }
        for issue_id in sorted(value for value in affected if value):
            rows = db.execute(
                "SELECT entity_id,operation,data_json FROM v2_entities "
                "WHERE entity_type='copy' AND issue_id=?",
                (issue_id,),
            ).fetchall()
            copies = {
                row["entity_id"]: {
                    "operation": row["operation"],
                    "data": json.loads(row["data_json"]),
                }
                for row in rows
            }
            copy_changes = [
                change
                for change in canonical
                if change["entity_type"] == "copy"
                and change["data"]["issue_id"] == issue_id
            ]
            for change in copy_changes:
                copies[change["entity_id"]] = change
            active_count = sum(
                1
                for copy in copies.values()
                if copy["operation"] != "delete"
                and not copy["data"].get("deleted", False)
                and copy["data"].get("active", False)
            )
            entry = next(
                (
                    change
                    for change in canonical
                    if change["entity_type"] == "collection_entry"
                    and change["entity_id"] == issue_id
                ),
                None,
            )
            if entry is None and copy_changes:
                stored = self._entity(db, "collection_entry", issue_id)
                if stored is not None:
                    entry = {
                        "entity_type": "collection_entry",
                        "entity_id": issue_id,
                        "operation": stored["operation"],
                        "data": dict(stored["data"]),
                    }
                else:
                    hint = next(
                        (
                            change["data"].get("issue_hint")
                            for change in copy_changes
                            if change["data"].get("issue_hint") is not None
                        ),
                        None,
                    )
                    entry = {
                        "entity_type": "collection_entry",
                        "entity_id": issue_id,
                        "operation": "upsert",
                        "data": {
                            "issue_id": issue_id,
                            "owned": False,
                            "is_wanted": True,
                            "is_read": False,
                            "is_duplicate": False,
                            "rating": 0,
                            "notes": "",
                            "deleted": False,
                            "updated_at": max(
                                (
                                    int(change["data"].get("updated_at", 0))
                                    for change in copy_changes
                                ),
                                default=0,
                            ),
                            "issue_hint": hint,
                        },
                    }
                canonical.append(entry)
            if entry is None:
                continue
            data = entry["data"]
            if entry["operation"] == "delete" or data.get("deleted", False):
                if active_count:
                    # Collection deletion uses observed-remove semantics. An
                    # active copy created on another device is independent
                    # user data and therefore wins over a stale aggregate
                    # deletion which did not observe/tombstone that copy.
                    # Canonicalizing instead of rejecting is important: the
                    # mutation is acknowledged and cannot poison the client's
                    # durable outbox forever.
                    requested = data
                    stored = self._entity(db, "collection_entry", issue_id)
                    if (
                        stored is not None
                        and stored["operation"] != "delete"
                        and not stored["data"].get("deleted", False)
                    ):
                        # A delete intent must not overwrite unrelated fields
                        # such as read/rating/notes with a stale device's
                        # snapshot. The server entry remains authoritative for
                        # those non-derived fields.
                        data = dict(stored["data"])
                        if (
                            data.get("issue_hint") is None
                            and requested.get("issue_hint") is not None
                        ):
                            data["issue_hint"] = requested["issue_hint"]
                        entry["data"] = data
                    entry["operation"] = "upsert"
                    data["deleted"] = False
                else:
                    data["owned"] = False
                    data["is_duplicate"] = False
                    data["is_wanted"] = False
                    continue
            data["owned"] = active_count > 0
            data["is_duplicate"] = active_count > 1
            data["is_wanted"] = active_count == 0
        return canonical

    @staticmethod
    def _entity(
        db: sqlite3.Connection, entity_type: str, entity_id: str
    ) -> dict | None:
        row = db.execute(
            "SELECT operation,data_json,revision FROM v2_entities "
            "WHERE entity_type=? AND entity_id=?",
            (entity_type, entity_id),
        ).fetchone()
        if row is None:
            return None
        return {
            "operation": row["operation"],
            "data": json.loads(row["data_json"]),
            "revision": row["revision"],
        }

    def _refresh_v1_projection(self, db: sqlite3.Connection, issue_id: str) -> None:
        issue = self._entity(db, "custom_issue", issue_id)
        entry = self._entity(db, "collection_entry", issue_id)
        existing = db.execute("SELECT * FROM comics WHERE id=?", (issue_id,)).fetchone()
        if entry is None and existing is None:
            return
        entry_data = entry["data"] if entry is not None else {}
        copy_rows = db.execute(
            "SELECT entity_id,operation,data_json FROM v2_entities "
            "WHERE entity_type='copy' AND issue_id=?",
            (issue_id,),
        ).fetchall()
        copies = []
        for row in copy_rows:
            data = json.loads(row["data_json"])
            if data.get("issue_id") == issue_id and row["operation"] != "delete":
                copies.append((row["entity_id"], data))
        copies.sort(key=lambda item: (item[1].get("ordinal", 0), item[0]))
        issue_hint = entry_data.get("issue_hint")
        if not isinstance(issue_hint, dict):
            issue_hint = next(
                (
                    data.get("issue_hint")
                    for _, data in copies
                    if isinstance(data.get("issue_hint"), dict)
                ),
                None,
            )
        if issue is None and issue_hint is None:
            return
        issue_data = issue["data"] if issue is not None else issue_hint
        active = [item[1] for item in copies if item[1].get("active")]
        primary = active[0] if active else (copies[0][1] if copies else {})
        previous_time = int(existing["updated_at"]) if existing is not None else 0
        updated_at = max(int(time.time() * 1000), previous_time + 1)
        deleted = (
            (issue is not None and issue["operation"] == "delete")
            or entry is None
            or entry["operation"] == "delete"
            or bool(entry_data.get("deleted", False))
        )
        clean = validate_comic(
            {
                "id": issue_id,
                "series": issue_data.get("series", ""),
                "edition": issue_data.get("edition", ""),
                "number": issue_data.get("number", 0),
                "title": issue_data.get("title", ""),
                "publisher": issue_data.get("publisher", ""),
                "year": issue_data.get("year"),
                "owned": bool(active),
                "is_read": bool(entry_data.get("is_read", False)),
                "condition_grade": primary.get("condition_grade", ""),
                "purchase_price": primary.get("purchase_price"),
                "estimated_value": primary.get("estimated_value"),
                "is_duplicate": len(active) > 1,
                "loaned_to": primary.get("loaned_to", ""),
                "notes": entry_data.get("notes", ""),
                "cover_asset": existing["cover_asset"] if existing is not None else "",
                "rating": entry_data.get("rating", 0),
                "page_count": issue_data.get("page_count"),
                "writer": issue_data.get("writer", ""),
                "artist": issue_data.get("artist", ""),
                "deleted": deleted,
                "updated_at": updated_at,
            }
        )
        db.execute(UPSERT, [clean[field] for field in FIELDS])

    def stats(self) -> dict:
        with closing(self.connect()) as db:
            row = db.execute("SELECT COUNT(*) total, SUM(CASE WHEN deleted=0 THEN 1 ELSE 0 END) active FROM comics").fetchone()
        return {"records": row["total"], "active": row["active"] or 0}

    def backup(self, destination: Path) -> Path:
        destination.mkdir(parents=True, exist_ok=True)
        target = destination / time.strftime("comicollect-%Y%m%d-%H%M%S.sqlite3")
        with self.lock, closing(self.connect()) as source, closing(
            sqlite3.connect(target)
        ) as dest:
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
    condition_grade = text("condition_grade", 8) if "condition_grade" in raw else "F"
    comic = {
        "id": text("id", 64), "series": text("series", 200), "edition": text("edition", 200),
        "number": int(raw["number"]), "title": text("title", 500), "publisher": text("publisher", 200),
        "year": int(raw["year"]) if raw.get("year") is not None else None,
        "owned": int(bool(raw.get("owned"))), "is_read": int(bool(raw.get("is_read"))),
        "condition_grade": condition_grade,
        "purchase_price": float(raw["purchase_price"]) if raw.get("purchase_price") is not None else None,
        "estimated_value": float(raw["estimated_value"]) if raw.get("estimated_value") is not None else None,
        "is_duplicate": int(bool(raw.get("is_duplicate"))), "loaned_to": text("loaned_to", 300),
        "notes": text("notes", 10000), "cover_asset": text("cover_asset", 500),
        "rating": max(0, min(5, int(raw.get("rating", 0)))),
        "page_count": int(raw["page_count"]) if raw.get("page_count") is not None else None,
        "writer": text("writer", 300), "artist": text("artist", 300),
        "deleted": int(bool(raw.get("deleted"))),
        "updated_at": int(raw["updated_at"]),
    }
    if not comic["id"] or not comic["series"] or comic["number"] < 0:
        raise ValueError("invalid id, series, or number")
    if comic["condition_grade"] not in CONDITION_GRADES:
        raise ValueError("invalid condition_grade")
    return comic


def validate_v2_request(raw: object) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("request must be an object")
    required = {
        "protocol",
        "request_id",
        "device_id",
        "cursor",
        "limit",
        "mutations",
    }
    allowed = required | {"server_id"}
    _require_keys(raw, required, allowed, "request")
    if type(raw["protocol"]) is not int or raw["protocol"] != 2:
        raise ValueError("protocol must be 2")
    request_id = _identifier(raw["request_id"], "request_id", 128)
    device_id = _identifier(raw["device_id"], "device_id", 128)
    server_id = raw.get("server_id", "")
    if server_id != "":
        server_id = _identifier(server_id, "server_id", 128)
    cursor = _integer(raw["cursor"], "cursor", minimum=0)
    limit = _integer(raw["limit"], "limit", minimum=1, maximum=MAX_V2_LIMIT)
    mutations = raw["mutations"]
    if not isinstance(mutations, list):
        raise ValueError("mutations must be an array")
    if len(mutations) > MAX_V2_MUTATIONS:
        raise ValueError(f"mutations may contain at most {MAX_V2_MUTATIONS} items")
    normalized = []
    mutation_ids = set()
    total_changes = 0
    for index, mutation in enumerate(mutations):
        label = f"mutations[{index}]"
        if not isinstance(mutation, dict):
            raise ValueError(f"{label} must be an object")
        keys = {"mutation_id", "created_at", "changes"}
        _require_keys(mutation, keys, keys, label)
        mutation_id = _identifier(
            mutation["mutation_id"], f"{label}.mutation_id", 128
        )
        if mutation_id in mutation_ids:
            raise ValueError("mutation_id must be unique within a request")
        mutation_ids.add(mutation_id)
        created_at = _integer(
            mutation["created_at"],
            f"{label}.created_at",
            minimum=0,
            maximum=2**63 - 1,
        )
        changes = mutation["changes"]
        if not isinstance(changes, list) or not changes:
            raise ValueError(f"{label}.changes must be a non-empty array")
        if len(changes) > MAX_V2_CHANGES_PER_MUTATION:
            raise ValueError(
                f"{label}.changes may contain at most "
                f"{MAX_V2_CHANGES_PER_MUTATION} items"
            )
        total_changes += len(changes)
        if total_changes > MAX_V2_TOTAL_CHANGES:
            raise ValueError(
                f"request may contain at most {MAX_V2_TOTAL_CHANGES} changes"
            )
        normalized.append(
            {
                "mutation_id": mutation_id,
                "created_at": created_at,
                "changes": [
                    _validate_v2_change(change, f"{label}.changes[{change_index}]")
                    for change_index, change in enumerate(changes)
                ],
            }
        )
    result = {
        "protocol": 2,
        "request_id": request_id,
        "device_id": device_id,
        "cursor": cursor,
        "limit": limit,
        "mutations": normalized,
    }
    if server_id:
        result["server_id"] = server_id
    return result


def _validate_v2_change(raw: object, label: str) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    keys = {"entity_type", "entity_id", "operation", "data"}
    _require_keys(raw, keys, keys, label)
    entity_type = raw["entity_type"]
    if entity_type not in V2_ENTITY_TYPES:
        raise ValueError(f"{label}.entity_type is unsupported")
    entity_id = _identifier(
        raw["entity_id"],
        f"{label}.entity_id",
        512 if entity_type == "barcode_mapping" else 128,
    )
    operation = raw["operation"]
    if operation not in V2_OPERATIONS:
        raise ValueError(f"{label}.operation is unsupported")
    if entity_type == "custom_issue":
        data = _validate_issue_data(raw["data"], f"{label}.data")
    elif entity_type == "collection_entry":
        data = _validate_collection_data(raw["data"], f"{label}.data")
        if entity_id != data["issue_id"]:
            raise ValueError(f"{label}.entity_id must equal data.issue_id")
    elif entity_type == "copy":
        data = _validate_copy_data(raw["data"], f"{label}.data")
    else:
        data = _validate_barcode_data(raw["data"], f"{label}.data")
    if entity_type != "custom_issue":
        expected_deleted = operation == "delete"
        if data["deleted"] is not expected_deleted:
            raise ValueError(
                f"{label}.data.deleted must agree with operation"
            )
    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "operation": operation,
        "data": data,
    }


def _validate_issue_data(raw: object, label: str) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    required = {"series", "edition", "number", "title"}
    allowed = required | {"publisher", "year", "page_count", "writer", "artist"}
    _require_keys(raw, required, allowed, label)
    series = _text_value(raw["series"], f"{label}.series", 200, nonempty=True)
    edition = _text_value(raw["edition"], f"{label}.edition", 200)
    title = _text_value(raw["title"], f"{label}.title", 500, nonempty=True)
    year = _nullable_integer(raw.get("year"), f"{label}.year", 0, 3000)
    page_count = _nullable_integer(
        raw.get("page_count"), f"{label}.page_count", 0, 100000
    )
    return {
        "series": series,
        "edition": edition,
        "number": _integer(
            raw["number"], f"{label}.number", minimum=0, maximum=10**9
        ),
        "title": title,
        "publisher": _text_value(raw.get("publisher", ""), f"{label}.publisher", 200),
        "year": year,
        "page_count": page_count,
        "writer": _text_value(raw.get("writer", ""), f"{label}.writer", 300),
        "artist": _text_value(raw.get("artist", ""), f"{label}.artist", 300),
    }


def _issue_hint(raw: object, issue_id: str, label: str) -> dict | None:
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    value = dict(raw)
    hinted_id = value.pop("id", issue_id)
    if hinted_id != issue_id:
        raise ValueError(f"{label}.id must equal issue_id")
    origin = value.pop("origin", None)
    if origin not in {"bundled", "custom"}:
        raise ValueError(f"{label}.origin must be bundled or custom")
    allowed = {"series", "edition", "number", "title", "publisher", "year"}
    _require_keys(
        value,
        {"series", "edition", "number", "title"},
        allowed,
        label,
    )
    return {
        "id": issue_id,
        "series": _text_value(value["series"], f"{label}.series", 200, nonempty=True),
        "edition": _text_value(value["edition"], f"{label}.edition", 200),
        "number": _integer(
            value["number"], f"{label}.number", minimum=0, maximum=10**9
        ),
        "title": _text_value(value["title"], f"{label}.title", 500, nonempty=True),
        "publisher": _text_value(
            value.get("publisher", ""), f"{label}.publisher", 200
        ),
        "year": _nullable_integer(value.get("year"), f"{label}.year", 0, 3000),
        "origin": origin,
    }


def _validate_collection_data(raw: object, label: str) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    required = {
        "issue_id",
        "owned",
        "is_wanted",
        "is_read",
        "is_duplicate",
        "rating",
        "notes",
        "deleted",
        "updated_at",
    }
    allowed = required | {"issue_hint"}
    _require_keys(raw, required, allowed, label)
    issue_id = _identifier(raw["issue_id"], f"{label}.issue_id", 128)
    return {
        "issue_id": issue_id,
        "owned": _boolean(raw["owned"], f"{label}.owned"),
        "is_wanted": _boolean(raw["is_wanted"], f"{label}.is_wanted"),
        "is_read": _boolean(raw["is_read"], f"{label}.is_read"),
        "is_duplicate": _boolean(
            raw["is_duplicate"], f"{label}.is_duplicate"
        ),
        "rating": _integer(raw["rating"], f"{label}.rating", minimum=0, maximum=5),
        "notes": _text_value(raw["notes"], f"{label}.notes", 10000),
        "deleted": _boolean(raw["deleted"], f"{label}.deleted"),
        "updated_at": _integer(
            raw["updated_at"],
            f"{label}.updated_at",
            minimum=0,
            maximum=2**63 - 1,
        ),
        "issue_hint": _issue_hint(
            raw.get("issue_hint"), issue_id, f"{label}.issue_hint"
        ),
    }


def _validate_copy_data(raw: object, label: str) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    required = {
        "issue_id",
        "ordinal",
        "active",
        "condition_grade",
        "purchase_price",
        "estimated_value",
        "loaned_to",
        "deleted",
        "updated_at",
    }
    allowed = required | {"issue_hint"}
    _require_keys(raw, required, allowed, label)
    issue_id = _identifier(raw["issue_id"], f"{label}.issue_id", 128)
    condition = _text_value(
        raw["condition_grade"], f"{label}.condition_grade", 8
    )
    if condition not in CONDITION_GRADES:
        raise ValueError(f"{label}.condition_grade is invalid")
    return {
        "issue_id": issue_id,
        "ordinal": _integer(
            raw["ordinal"], f"{label}.ordinal", minimum=0, maximum=10**6
        ),
        "active": _boolean(raw["active"], f"{label}.active"),
        "condition_grade": condition,
        "purchase_price": _nullable_number(
            raw["purchase_price"], f"{label}.purchase_price"
        ),
        "estimated_value": _nullable_number(
            raw["estimated_value"], f"{label}.estimated_value"
        ),
        "loaned_to": _text_value(raw["loaned_to"], f"{label}.loaned_to", 300),
        "deleted": _boolean(raw["deleted"], f"{label}.deleted"),
        "updated_at": _integer(
            raw["updated_at"],
            f"{label}.updated_at",
            minimum=0,
            maximum=2**63 - 1,
        ),
        "issue_hint": _issue_hint(
            raw.get("issue_hint"), issue_id, f"{label}.issue_hint"
        ),
    }


def _validate_barcode_data(raw: object, label: str) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"{label} must be an object")
    required = {"issue_id", "deleted", "updated_at"}
    allowed = required | {"issue_hint"}
    _require_keys(raw, required, allowed, label)
    issue_id = _identifier(raw["issue_id"], f"{label}.issue_id", 128)
    return {
        "issue_id": issue_id,
        "deleted": _boolean(raw["deleted"], f"{label}.deleted"),
        "updated_at": _integer(
            raw["updated_at"],
            f"{label}.updated_at",
            minimum=0,
            maximum=2**63 - 1,
        ),
        "issue_hint": _issue_hint(
            raw.get("issue_hint"), issue_id, f"{label}.issue_hint"
        ),
    }


def _canonical_change(change: dict) -> dict:
    data = dict(change["data"])
    if change["entity_type"] == "custom_issue":
        data["deleted"] = change["operation"] == "delete"
    return {
        "entity_type": change["entity_type"],
        "entity_id": change["entity_id"],
        "operation": change["operation"],
        "data": data,
    }


def _v1_changes(comic: dict) -> list[dict]:
    comic = _sanitize_v1_for_v2(comic)
    issue_id = comic["id"]
    deleted = bool(comic["deleted"])
    issue = {
        "entity_type": "custom_issue",
        "entity_id": issue_id,
        "operation": "upsert",
        "data": {
            "series": comic["series"],
            "edition": comic["edition"],
            "number": comic["number"],
            "title": comic["title"],
            "publisher": comic["publisher"],
            "year": comic["year"],
            "page_count": comic["page_count"],
            "writer": comic["writer"],
            "artist": comic["artist"],
        },
    }
    entry = {
        "entity_type": "collection_entry",
        "entity_id": issue_id,
        "operation": "delete" if deleted else "upsert",
        "data": {
            "issue_id": issue_id,
            "owned": bool(comic["owned"]),
            "is_wanted": not bool(comic["owned"]) and not deleted,
            "is_read": bool(comic["is_read"]),
            "is_duplicate": bool(comic["is_duplicate"]),
            "rating": comic["rating"],
            "notes": comic["notes"],
            "deleted": deleted,
            "updated_at": comic["updated_at"],
        },
    }
    primary = {
        "entity_type": "copy",
        "entity_id": f"{issue_id}:copy:0",
        "operation": "delete" if deleted else "upsert",
        "data": {
            "issue_id": issue_id,
            "ordinal": 0,
            "active": bool(comic["owned"]) and not deleted,
            "condition_grade": comic["condition_grade"],
            "purchase_price": comic["purchase_price"],
            "estimated_value": comic["estimated_value"],
            "loaned_to": comic["loaned_to"],
            "deleted": deleted,
            "updated_at": comic["updated_at"],
        },
    }
    duplicate = bool(comic["is_duplicate"]) and not deleted
    secondary = {
        "entity_type": "copy",
        "entity_id": f"{issue_id}:copy:1",
        "operation": "upsert" if duplicate else "delete",
        "data": {
            "issue_id": issue_id,
            "ordinal": 1,
            "active": duplicate and bool(comic["owned"]),
            "condition_grade": "",
            "purchase_price": None,
            "estimated_value": None,
            "loaned_to": "",
            "deleted": not duplicate,
            "updated_at": comic["updated_at"],
        },
    }
    return [issue, entry, primary, secondary]


def _sanitize_v1_for_v2(comic: dict) -> dict:
    """Map every historically accepted v1 row to a re-uploadable v2 state."""
    value = dict(comic)
    raw_id = str(value.get("id", ""))
    try:
        issue_id = _identifier(raw_id, "legacy id", 128)
    except ValueError:
        issue_id = "legacy-" + hashlib.sha256(raw_id.encode("utf-8")).hexdigest()
    number = max(0, min(10**9, int(value.get("number", 0))))
    series = _truncate_utf8(str(value.get("series", "")).strip(), 200)
    if not series:
        series = "Legacy comic"
    title = _truncate_utf8(str(value.get("title", "")).strip(), 500)
    if not title:
        title = _truncate_utf8(f"{series} #{number}", 500)
    year = value.get("year")
    year = (
        int(year)
        if isinstance(year, (int, float))
        and not isinstance(year, bool)
        and 0 <= int(year) <= 3000
        else None
    )
    page_count = value.get("page_count")
    page_count = (
        int(page_count)
        if isinstance(page_count, (int, float))
        and not isinstance(page_count, bool)
        and 0 <= int(page_count) <= 100000
        else None
    )
    updated_at = value.get("updated_at")
    updated_at = (
        max(0, min(2**63 - 1, int(updated_at)))
        if isinstance(updated_at, (int, float)) and not isinstance(updated_at, bool)
        else 0
    )

    def price(field: str) -> float | None:
        raw = value.get(field)
        if isinstance(raw, bool) or not isinstance(raw, (int, float)):
            return None
        result = float(raw)
        return result if math.isfinite(result) and result >= 0 else None

    value.update(
        {
            "id": issue_id,
            "series": series,
            "edition": _truncate_utf8(str(value.get("edition", "")), 200),
            "number": number,
            "title": title,
            "publisher": _truncate_utf8(str(value.get("publisher", "")), 200),
            "year": year,
            "page_count": page_count,
            "writer": _truncate_utf8(str(value.get("writer", "")), 300),
            "artist": _truncate_utf8(str(value.get("artist", "")), 300),
            "notes": _truncate_utf8(str(value.get("notes", "")), 10000),
            "loaned_to": _truncate_utf8(str(value.get("loaned_to", "")), 300),
            "purchase_price": price("purchase_price"),
            "estimated_value": price("estimated_value"),
            "updated_at": updated_at,
        }
    )
    return value


def _truncate_utf8(value: str, byte_limit: int) -> str:
    encoded = value.encode("utf-8")
    if len(encoded) <= byte_limit:
        return value
    return encoded[:byte_limit].decode("utf-8", errors="ignore")


def _change_issue_id(change: dict) -> str | None:
    if change["entity_type"] == "custom_issue":
        return change["entity_id"]
    issue_id = change["data"].get("issue_id")
    return issue_id if isinstance(issue_id, str) else None


def _require_keys(
    value: dict, required: set[str], allowed: set[str], label: str
) -> None:
    missing = required - value.keys()
    unknown = value.keys() - allowed
    if missing:
        raise ValueError(f"{label} is missing: {', '.join(sorted(missing))}")
    if unknown:
        raise ValueError(f"{label} has unknown fields: {', '.join(sorted(unknown))}")


def _identifier(value: object, label: str, limit: int) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"{label} must be a non-empty trimmed string")
    if len(value.encode("utf-8")) > limit or not IDENTIFIER_RE.fullmatch(value):
        raise ValueError(f"{label} is invalid or exceeds {limit} bytes")
    return value


def _text_value(
    value: object, label: str, limit: int, *, nonempty: bool = False
) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{label} must be a string")
    if nonempty and not value.strip():
        raise ValueError(f"{label} must not be empty")
    if len(value.encode("utf-8")) > limit:
        raise ValueError(f"{label} exceeds {limit} bytes")
    return value


def _integer(
    value: object,
    label: str,
    *,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    if type(value) is not int:
        raise ValueError(f"{label} must be an integer")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} must be at least {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{label} must be at most {maximum}")
    return value


def _nullable_integer(
    value: object, label: str, minimum: int, maximum: int
) -> int | None:
    if value is None:
        return None
    return _integer(value, label, minimum=minimum, maximum=maximum)


def _nullable_number(value: object, label: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a finite non-negative number or null")
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise ValueError(f"{label} must be a finite non-negative number or null")
    return number


def _boolean(value: object, label: str) -> bool:
    if type(value) is not bool:
        raise ValueError(f"{label} must be a boolean")
    return value


def _canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _payload_hash(value: object) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "Comicollect/2.0"

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
            self.json_response(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "version": 2,
                    "server_id": self.server.store.server_id,
                    "protocols": [1, 2],
                    **self.server.store.stats(),
                },
            )
        else:
            self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path not in {"/api/v1/sync", "/api/v2/sync"}:
            return self.json_response(HTTPStatus.NOT_FOUND, {"error": "not found"})
        if not self.authorized():
            return self.json_response(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > MAX_BODY and self.path == "/api/v2/sync":
                raise ApiError(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    "request_too_large",
                    "request body exceeds the configured limit",
                )
            if length <= 0 or length > MAX_BODY:
                raise ValueError("invalid body size")
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0]
            if self.path == "/api/v2/sync" and content_type.lower() != "application/json":
                raise ApiError(
                    HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
                    "unsupported_media_type",
                    "Content-Type must be application/json",
                )
            payload = json.loads(
                self.rfile.read(length),
                parse_constant=lambda value: (_ for _ in ()).throw(
                    ValueError(f"invalid JSON constant {value}")
                ),
            )
            if self.path == "/api/v2/sync":
                response = self.server.store.sync_v2(payload)
            else:
                if not isinstance(payload, dict):
                    raise ValueError("request must be an object")
                since = max(0, int(payload.get("since", 0)))
                changes = payload.get("changes", [])
                if not isinstance(changes, list) or len(changes) > 10000:
                    raise ValueError("invalid changes")
                server_time, remote = self.server.store.sync(since, changes)
                response = {"server_time": server_time, "changes": remote}
            self.json_response(HTTPStatus.OK, response)
        except ApiError as exc:
            self.json_response(exc.status, exc.payload())
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            payload = {"error": str(exc)}
            if self.path == "/api/v2/sync":
                payload["code"] = "invalid_request"
            self.json_response(HTTPStatus.BAD_REQUEST, payload)
        except Exception as exc:
            # Legacy mode follows the same redaction rule as production: an
            # exception message may itself contain a credential or private
            # database value, so routine logs keep only its class.
            LOG.error("sync failed; failure_type=%s", type(exc).__name__)
            self.json_response(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal error"})


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def __init__(self, address, store: Store, api_token: str):
        super().__init__(address, ApiHandler)
        self.store, self.api_token = store, api_token


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=("production", "legacy"),
        default=os.getenv("COMICOLLECT_MODE", "production"),
        help="production accounts are the default; legacy keeps the shared LAN token",
    )
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--db", type=Path, default=Path(os.getenv("COMICOLLECT_DB", "./data/comicollect.sqlite3")))
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--backup-dir", type=Path, default=Path(os.getenv("COMICOLLECT_BACKUP_DIR", "./backups")))
    args = parser.parse_args()
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
    if args.mode == "production":
        from comicollect_backend import (
            AuthRepository,
            AuthService,
            PasswordHasher,
            ProductionApi,
            ProductionHttpServer,
            TenantStore,
            load_config,
        )

        try:
            config = load_config()
        except (OSError, ValueError) as exc:
            raise SystemExit(f"invalid production configuration: {exc}") from exc
        os.umask(0o077)
        tenants = TenantStore(
            config.tenant_root,
            maximum_tenant_bytes=config.tenant_storage_limit_bytes,
            minimum_free_bytes=config.disk_reserve_bytes,
        )
        if args.backup and not config.auth_database.is_file():
            raise SystemExit(
                "production backup requires an existing auth database"
            )
        try:
            repository = AuthRepository(config.auth_database)
            auth = AuthService(
                repository,
                PasswordHasher(config.password_pepper, config.scrypt),
                registration_enabled=config.registration_enabled,
                access_ttl_ms=config.access_ttl_ms,
                refresh_ttl_ms=config.refresh_ttl_ms,
                session_ttl_ms=config.session_ttl_ms,
            )
        except (OSError, ValueError, sqlite3.DatabaseError) as exc:
            if args.backup:
                raise SystemExit(
                    f"production backup validation failed: {exc}"
                )
            raise
        if args.backup:
            try:
                print(tenants.backup_all(config.auth_database, args.backup_dir))
            except (OSError, ValueError, RuntimeError, sqlite3.DatabaseError) as exc:
                raise SystemExit(f"production backup failed: {exc}")
            return
        api = ProductionApi(auth, tenants)
        host = args.host or config.host
        port = config.port if args.port is None else args.port
        if not 1 <= port <= 65535:
            raise SystemExit("port must be between 1 and 65535")
        LOG.info(
            "production backend listening on %s:%s; auth_database=%s",
            host,
            port,
            config.auth_database,
        )
        ProductionHttpServer((host, port), api).serve_forever()
        return

    host = args.host or os.getenv("COMICOLLECT_HOST", "0.0.0.0")
    port = (
        int(os.getenv("COMICOLLECT_PORT", "8787"))
        if args.port is None
        else args.port
    )
    if not 1 <= port <= 65535:
        raise SystemExit("port must be between 1 and 65535")
    store = Store(args.db)
    if args.backup:
        print(store.backup(args.backup_dir))
        return
    token = os.getenv("COMICOLLECT_TOKEN", "")
    if len(token) < 32:
        raise SystemExit(
            "legacy mode requires COMICOLLECT_TOKEN with at least 32 characters"
        )
    LOG.warning("legacy shared-token mode is enabled")
    LOG.info("listening on %s:%s; database=%s", host, port, args.db)
    Server((host, port), store, token).serve_forever()


if __name__ == "__main__":
    main()
