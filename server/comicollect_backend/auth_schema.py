"""Auth database schema, migrations, and bounded retention policies."""

from __future__ import annotations

import sqlite3


SUPPORTED_AUTH_SCHEMA_VERSION = 2
MAX_ACTIVE_SESSIONS_PER_ACCOUNT = 10
MAX_RETAINED_REVOKED_SESSIONS_PER_ACCOUNT = 50
MAX_ACCESS_TOKENS_PER_SESSION = 4
_SESSION_RETENTION_GRACE_MS = 7 * 24 * 60 * 60 * 1000


def initialize_auth_schema(db: sqlite3.Connection) -> None:
    """Create or migrate the auth schema and reject unsafe downgrades."""

    db.execute(
        "CREATE TABLE IF NOT EXISTS auth_schema_migrations("
        "version INTEGER PRIMARY KEY,applied_at INTEGER NOT NULL)"
    )
    latest = int(
        db.execute(
            "SELECT COALESCE(MAX(version),0) FROM auth_schema_migrations"
        ).fetchone()[0]
    )
    if latest > SUPPORTED_AUTH_SCHEMA_VERSION:
        raise RuntimeError(
            "database uses a newer auth schema "
            f"({latest} > {SUPPORTED_AUTH_SCHEMA_VERSION})"
        )

    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS auth_meta(
          key TEXT PRIMARY KEY,
          value BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS accounts(
          id TEXT PRIMARY KEY,
          email TEXT NOT NULL UNIQUE,
          display_name TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'active'
            CHECK(status IN ('active','suspended','deleting')),
          email_verified_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS auth_sessions(
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL REFERENCES accounts(id),
          installation_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL,
          absolute_expires_at INTEGER NOT NULL,
          revoked_at INTEGER,
          revoke_reason TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_auth_sessions_account
          ON auth_sessions(account_id, revoked_at);
        CREATE INDEX IF NOT EXISTS idx_auth_sessions_expiry
          ON auth_sessions(absolute_expires_at, revoked_at);
        CREATE TABLE IF NOT EXISTS auth_access_tokens(
          token_digest BLOB PRIMARY KEY,
          token_nonce BLOB NOT NULL,
          session_id TEXT NOT NULL REFERENCES auth_sessions(id),
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_access_session
          ON auth_access_tokens(session_id);
        CREATE TABLE IF NOT EXISTS auth_refresh_tokens(
          token_digest BLOB PRIMARY KEY,
          token_nonce BLOB NOT NULL,
          session_id TEXT NOT NULL REFERENCES auth_sessions(id),
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          consumed_at INTEGER,
          refresh_request_id TEXT,
          replacement_digest BLOB,
          replacement_access_digest BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_refresh_session
          ON auth_refresh_tokens(session_id);
        CREATE TABLE IF NOT EXISTS auth_action_tokens(
          token_digest BLOB PRIMARY KEY,
          token_nonce BLOB NOT NULL,
          account_id TEXT NOT NULL REFERENCES accounts(id),
          purpose TEXT NOT NULL
            CHECK(purpose IN ('email_verification','password_reset')),
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          superseded_at INTEGER,
          consumed_at INTEGER,
          consume_request_id TEXT,
          consume_payload_digest BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_action_account_purpose
          ON auth_action_tokens(account_id,purpose,created_at);
        CREATE INDEX IF NOT EXISTS idx_action_expiry
          ON auth_action_tokens(expires_at);
        """
    )
    _ensure_column(db, "auth_access_tokens", "token_nonce", "BLOB")
    _ensure_column(
        db,
        "accounts",
        "email_verification_required",
        "INTEGER NOT NULL DEFAULT 0 CHECK(email_verification_required IN (0,1))",
    )
    _ensure_column(db, "auth_refresh_tokens", "token_nonce", "BLOB")
    _ensure_column(db, "auth_refresh_tokens", "refresh_request_id", "TEXT")
    _ensure_column(
        db,
        "auth_refresh_tokens",
        "replacement_access_digest",
        "BLOB",
    )
    db.execute(
        "INSERT OR IGNORE INTO auth_schema_migrations(version,applied_at) "
        "VALUES(1,CAST(strftime('%s','now') AS INTEGER) * 1000)"
    )
    db.execute(
        "INSERT OR IGNORE INTO auth_schema_migrations(version,applied_at) "
        "VALUES(2,CAST(strftime('%s','now') AS INTEGER) * 1000)"
    )


def prune_stale_sessions(db: sqlite3.Connection, now: int) -> None:
    db.execute(
        "UPDATE auth_sessions SET revoked_at=?,revoke_reason='session_expired' "
        "WHERE revoked_at IS NULL AND absolute_expires_at<=?",
        (now, now),
    )
    cutoff = now - _SESSION_RETENTION_GRACE_MS
    stale = db.execute(
        "SELECT id FROM auth_sessions WHERE "
        "absolute_expires_at<? OR (revoked_at IS NOT NULL AND revoked_at<?)",
        (cutoff, cutoff),
    ).fetchall()
    _delete_sessions(db, [str(row["id"]) for row in stale])


def prepare_new_session(
    db: sqlite3.Connection,
    *,
    account_id: str,
    installation_id: str,
    now: int,
) -> None:
    """Revoke replaced/overflow sessions before one new session is inserted."""

    replaced = db.execute(
        "SELECT id FROM auth_sessions WHERE account_id=? AND installation_id=? "
        "AND revoked_at IS NULL",
        (account_id, installation_id),
    ).fetchall()
    replaced_ids = [str(row["id"]) for row in replaced]
    _revoke_sessions(db, replaced_ids, now, "installation_replaced")
    _delete_session_tokens(db, replaced_ids)

    active = db.execute(
        "SELECT id FROM auth_sessions WHERE account_id=? AND revoked_at IS NULL "
        "ORDER BY last_seen_at DESC,created_at DESC,id DESC",
        (account_id,),
    ).fetchall()
    keep_before_insert = MAX_ACTIVE_SESSIONS_PER_ACCOUNT - 1
    overflow_ids = [str(row["id"]) for row in active[keep_before_insert:]]
    _revoke_sessions(db, overflow_ids, now, "account_session_limit")
    _delete_session_tokens(db, overflow_ids)
    trim_revoked_sessions(db, account_id)


def trim_revoked_sessions(db: sqlite3.Connection, account_id: str) -> None:
    stale = db.execute(
        "SELECT id FROM auth_sessions WHERE account_id=? AND revoked_at IS NOT NULL "
        "ORDER BY revoked_at DESC,created_at DESC,id DESC LIMIT -1 OFFSET ?",
        (account_id, MAX_RETAINED_REVOKED_SESSIONS_PER_ACCOUNT),
    ).fetchall()
    _delete_sessions(db, [str(row["id"]) for row in stale])


def prune_expired_tokens(db: sqlite3.Connection, now: int) -> None:
    """Drop expired credentials while preserving one retryable refresh parent."""

    db.execute(
        "DELETE FROM auth_refresh_tokens "
        "WHERE consumed_at IS NULL AND expires_at<=?",
        (now,),
    )
    db.execute(
        "DELETE FROM auth_refresh_tokens AS parent "
        "WHERE parent.consumed_at IS NOT NULL AND NOT EXISTS("
        "SELECT 1 FROM auth_refresh_tokens AS current "
        "WHERE current.token_digest=parent.replacement_digest "
        "AND current.consumed_at IS NULL AND current.expires_at>?)",
        (now,),
    )
    db.execute(
        "DELETE FROM auth_access_tokens AS access "
        "WHERE access.expires_at<=? AND NOT EXISTS("
        "SELECT 1 FROM auth_refresh_tokens AS parent "
        "JOIN auth_refresh_tokens AS current "
        "ON current.token_digest=parent.replacement_digest "
        "WHERE parent.replacement_access_digest=access.token_digest "
        "AND parent.consumed_at IS NOT NULL "
        "AND current.consumed_at IS NULL AND current.expires_at>?)",
        (now, now),
    )


def prune_session_token_family(
    db: sqlite3.Connection,
    session_id: str,
    now: int,
) -> None:
    """Keep the current refresh and only its immediate consumed parent."""

    current = db.execute(
        "SELECT token_digest FROM auth_refresh_tokens "
        "WHERE session_id=? AND consumed_at IS NULL AND expires_at>? "
        "ORDER BY created_at DESC,rowid DESC LIMIT 1",
        (session_id, now),
    ).fetchone()
    allowed_refresh: list[bytes] = []
    protected_access: bytes | None = None
    if current is not None:
        current_digest = bytes(current["token_digest"])
        allowed_refresh.append(current_digest)
        parent = db.execute(
            "SELECT token_digest,replacement_access_digest "
            "FROM auth_refresh_tokens WHERE session_id=? "
            "AND consumed_at IS NOT NULL AND replacement_digest=? "
            "ORDER BY consumed_at DESC,rowid DESC LIMIT 1",
            (session_id, current_digest),
        ).fetchone()
        if parent is not None:
            allowed_refresh.append(bytes(parent["token_digest"]))
            if parent["replacement_access_digest"] is not None:
                protected_access = bytes(parent["replacement_access_digest"])

    if allowed_refresh:
        placeholders = ",".join("?" for _ in allowed_refresh)
        db.execute(
            "DELETE FROM auth_refresh_tokens WHERE session_id=? "
            f"AND token_digest NOT IN ({placeholders})",
            (session_id, *allowed_refresh),
        )
    else:
        db.execute(
            "DELETE FROM auth_refresh_tokens WHERE session_id=?",
            (session_id,),
        )

    rows = db.execute(
        "SELECT token_digest,expires_at FROM auth_access_tokens "
        "WHERE session_id=? ORDER BY created_at DESC,rowid DESC",
        (session_id,),
    ).fetchall()
    keep: set[bytes] = set()
    for row in rows:
        digest = bytes(row["token_digest"])
        if int(row["expires_at"]) > now or digest == protected_access:
            if len(keep) < MAX_ACCESS_TOKENS_PER_SESSION or digest == protected_access:
                keep.add(digest)
    stale = [
        (bytes(row["token_digest"]),)
        for row in rows
        if bytes(row["token_digest"]) not in keep
    ]
    db.executemany(
        "DELETE FROM auth_access_tokens WHERE token_digest=?",
        stale,
    )


def _ensure_column(
    db: sqlite3.Connection,
    table: str,
    column: str,
    definition: str,
) -> None:
    columns = {str(row[1]) for row in db.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        db.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def _revoke_sessions(
    db: sqlite3.Connection,
    session_ids: list[str],
    now: int,
    reason: str,
) -> None:
    db.executemany(
        "UPDATE auth_sessions SET revoked_at=?,revoke_reason=? "
        "WHERE id=? AND revoked_at IS NULL",
        [(now, reason, session_id) for session_id in session_ids],
    )


def _delete_session_tokens(db: sqlite3.Connection, session_ids: list[str]) -> None:
    parameters = [(session_id,) for session_id in session_ids]
    db.executemany(
        "DELETE FROM auth_access_tokens WHERE session_id=?",
        parameters,
    )
    db.executemany(
        "DELETE FROM auth_refresh_tokens WHERE session_id=?",
        parameters,
    )


def _delete_sessions(db: sqlite3.Connection, session_ids: list[str]) -> None:
    if not session_ids:
        return
    _delete_session_tokens(db, session_ids)
    db.executemany(
        "DELETE FROM auth_sessions WHERE id=?",
        [(session_id,) for session_id in session_ids],
    )
