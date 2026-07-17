"""SQLite persistence for accounts and revocable sessions."""

from __future__ import annotations

import hmac
import sqlite3
import stat
import uuid
from contextlib import closing
from pathlib import Path
from threading import RLock

from .auth_models import AccessRecord, Account, AuthContext, RefreshRecord
from .auth_schema import (
    SUPPORTED_AUTH_SCHEMA_VERSION,
    initialize_auth_schema,
    prepare_new_session,
    prune_expired_tokens,
    prune_session_token_family,
    prune_stale_sessions,
)


_REQUIRED_AUTH_SCHEMA: dict[str, frozenset[str]] = {
    "auth_schema_migrations": frozenset({"version", "applied_at"}),
    "auth_meta": frozenset({"key", "value"}),
    "accounts": frozenset(
        {
            "id",
            "email",
            "display_name",
            "password_hash",
            "status",
            "email_verified_at",
            "created_at",
            "updated_at",
        }
    ),
    "auth_sessions": frozenset(
        {
            "id",
            "account_id",
            "installation_id",
            "created_at",
            "last_seen_at",
            "absolute_expires_at",
            "revoked_at",
            "revoke_reason",
        }
    ),
    "auth_access_tokens": frozenset(
        {
            "token_digest",
            "token_nonce",
            "session_id",
            "created_at",
            "expires_at",
        }
    ),
    "auth_refresh_tokens": frozenset(
        {
            "token_digest",
            "token_nonce",
            "session_id",
            "created_at",
            "expires_at",
            "consumed_at",
            "refresh_request_id",
            "replacement_digest",
            "replacement_access_digest",
        }
    ),
}


class DuplicateEmailError(Exception):
    pass


class AuthRepository:
    def __init__(self, path: Path | str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._lock = RLock()
        self._initialize()
        self.path.chmod(0o600)

    def connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA synchronous=FULL")
        db.execute("PRAGMA busy_timeout=15000")
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def _initialize(self) -> None:
        with closing(self.connect()) as db, db:
            # journal_mode is persistent database state; setting it on every
            # short-lived request connection adds an avoidable schema lock.
            db.execute("PRAGMA journal_mode=WAL")
            initialize_auth_schema(db)

    def bind_token_key(self, fingerprint: bytes) -> None:
        if not isinstance(fingerprint, bytes) or len(fingerprint) != 32:
            raise ValueError("token key fingerprint must contain 32 bytes")
        with self._lock, closing(self.connect()) as db, db:
            row = db.execute(
                "SELECT value FROM auth_meta WHERE key='token_key_fingerprint'"
            ).fetchone()
            if row is None:
                db.execute(
                    "INSERT INTO auth_meta(key,value) VALUES"
                    "('token_key_fingerprint',?)",
                    (fingerprint,),
                )
                return
            if not hmac.compare_digest(bytes(row[0]), fingerprint):
                raise ValueError("configured token key does not match this database")

    def create_account(
        self,
        *,
        email: str,
        display_name: str,
        password_hash: str,
        now: int,
    ) -> Account:
        account = Account(str(uuid.uuid4()), email, display_name, "active", None)
        try:
            with self._lock, closing(self.connect()) as db, db:
                _insert_account(db, account, password_hash=password_hash, now=now)
        except sqlite3.IntegrityError as exc:
            raise DuplicateEmailError() from exc
        return account

    def create_account_with_session(
        self,
        *,
        email: str,
        display_name: str,
        password_hash: str,
        installation_id: str,
        access_digest: bytes,
        access_nonce: bytes,
        access_expires_at: int,
        refresh_digest: bytes,
        refresh_nonce: bytes,
        refresh_expires_at: int,
        session_expires_at: int,
        now: int,
    ) -> Account:
        """Create a public account and its first session in one transaction."""

        account = Account(str(uuid.uuid4()), email, display_name, "active", None)
        session_id = str(uuid.uuid4())
        try:
            with self._lock, closing(self.connect()) as db, db:
                db.execute("BEGIN IMMEDIATE")
                _insert_account(db, account, password_hash=password_hash, now=now)
                prune_stale_sessions(db, now)
                prune_expired_tokens(db, now)
                _insert_session(
                    db,
                    session_id=session_id,
                    account_id=account.id,
                    installation_id=installation_id,
                    session_expires_at=session_expires_at,
                    now=now,
                )
                _insert_tokens(
                    db,
                    session_id=session_id,
                    access_digest=access_digest,
                    access_nonce=access_nonce,
                    access_expires_at=access_expires_at,
                    refresh_digest=refresh_digest,
                    refresh_nonce=refresh_nonce,
                    refresh_expires_at=refresh_expires_at,
                    now=now,
                )
        except sqlite3.IntegrityError as exc:
            if self.account_with_password(email) is not None:
                raise DuplicateEmailError() from exc
            raise
        return account

    def account_with_password(self, email: str) -> tuple[Account, str] | None:
        with closing(self.connect()) as db:
            row = db.execute(
                "SELECT * FROM accounts WHERE email=?", (email,)
            ).fetchone()
        if row is None:
            return None
        return _account(row), str(row["password_hash"])

    def update_password_hash(self, account_id: str, encoded: str, now: int) -> None:
        with self._lock, closing(self.connect()) as db, db:
            db.execute(
                "UPDATE accounts SET password_hash=?,updated_at=? WHERE id=?",
                (encoded, now, account_id),
            )

    def create_session(
        self,
        *,
        account_id: str,
        installation_id: str,
        access_digest: bytes,
        access_nonce: bytes,
        access_expires_at: int,
        refresh_digest: bytes,
        refresh_nonce: bytes,
        refresh_expires_at: int,
        session_expires_at: int,
        now: int,
    ) -> str:
        session_id = str(uuid.uuid4())
        with self._lock, closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            prune_stale_sessions(db, now)
            prune_expired_tokens(db, now)
            prepare_new_session(
                db,
                account_id=account_id,
                installation_id=installation_id,
                now=now,
            )
            _insert_session(
                db,
                session_id=session_id,
                account_id=account_id,
                installation_id=installation_id,
                session_expires_at=session_expires_at,
                now=now,
            )
            _insert_tokens(
                db,
                session_id=session_id,
                access_digest=access_digest,
                access_nonce=access_nonce,
                access_expires_at=access_expires_at,
                refresh_digest=refresh_digest,
                refresh_nonce=refresh_nonce,
                refresh_expires_at=refresh_expires_at,
                now=now,
            )
        return session_id

    def authenticate_access(self, digest: bytes, now: int) -> AccessRecord:
        with closing(self.connect()) as db:
            row = db.execute(
                "SELECT a.*,s.id session_id,s.revoked_at,s.absolute_expires_at,"
                "t.expires_at token_expires_at "
                "FROM auth_access_tokens t "
                "JOIN auth_sessions s ON s.id=t.session_id "
                "JOIN accounts a ON a.id=s.account_id "
                "WHERE t.token_digest=?",
                (digest,),
            ).fetchone()
        if row is None:
            return AccessRecord("invalid")
        if row["revoked_at"] is not None or row["status"] != "active":
            return AccessRecord("invalid")
        if (
            int(row["token_expires_at"]) <= now
            or int(row["absolute_expires_at"]) <= now
        ):
            return AccessRecord("expired")
        return AccessRecord(
            "active", AuthContext(_account(row), str(row["session_id"]))
        )

    def refresh_rate_limit_key(self, digest: bytes) -> str:
        """Return a stable session identity without exposing it on the wire."""

        with closing(self.connect()) as db:
            row = db.execute(
                "SELECT session_id FROM auth_refresh_tokens WHERE token_digest=?",
                (digest,),
            ).fetchone()
        if row is None:
            return "unknown:" + digest.hex()
        return "session:" + str(row["session_id"])

    def rotate_refresh(
        self,
        *,
        old_digest: bytes,
        installation_id: str,
        request_id: str,
        access_digest: bytes,
        access_nonce: bytes,
        access_expires_at: int,
        refresh_digest: bytes,
        refresh_nonce: bytes,
        refresh_expires_at: int,
        now: int,
    ) -> RefreshRecord:
        with self._lock, closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            prune_stale_sessions(db, now)
            row = db.execute(
                "SELECT a.*,s.id session_id,s.revoked_at,s.absolute_expires_at,"
                "s.installation_id,"
                "t.expires_at refresh_expires_at,t.consumed_at,"
                "t.refresh_request_id,t.replacement_digest,"
                "t.replacement_access_digest "
                "FROM auth_refresh_tokens t "
                "JOIN auth_sessions s ON s.id=t.session_id "
                "JOIN accounts a ON a.id=s.account_id "
                "WHERE t.token_digest=?",
                (old_digest,),
            ).fetchone()
            if row is None:
                prune_expired_tokens(db, now)
                return RefreshRecord("invalid")
            session_id = str(row["session_id"])
            if not hmac.compare_digest(
                str(row["installation_id"]), installation_id
            ):
                return RefreshRecord("installation_mismatch")
            if row["consumed_at"] is not None:
                if row["refresh_request_id"] == request_id:
                    if (
                        row["revoked_at"] is not None
                        or row["status"] != "active"
                        or int(row["absolute_expires_at"]) <= now
                    ):
                        return RefreshRecord("expired")
                    replacement = db.execute(
                        "SELECT a.token_nonce access_nonce,"
                        "a.expires_at access_expires_at,"
                        "r.token_nonce refresh_nonce,"
                        "r.expires_at next_refresh_expires_at,"
                        "r.consumed_at replacement_consumed_at "
                        "FROM auth_access_tokens a,auth_refresh_tokens r "
                        "WHERE a.token_digest=? AND r.token_digest=?",
                        (
                            row["replacement_access_digest"],
                            row["replacement_digest"],
                        ),
                    ).fetchone()
                    if replacement is None:
                        raise RuntimeError("refresh replacement is missing")
                    if replacement["replacement_consumed_at"] is not None:
                        db.execute(
                            "UPDATE auth_sessions SET revoked_at=?,"
                            "revoke_reason='refresh_replay' "
                            "WHERE id=? AND revoked_at IS NULL",
                            (now, session_id),
                        )
                        return RefreshRecord("replayed")
                    if int(replacement["next_refresh_expires_at"]) <= now:
                        return RefreshRecord("expired")
                    return RefreshRecord(
                        state="duplicate",
                        account=_account(row),
                        session_id=session_id,
                        session_expires_at=int(row["absolute_expires_at"]),
                        access_nonce=bytes(replacement["access_nonce"]),
                        refresh_nonce=bytes(replacement["refresh_nonce"]),
                        access_expires_at=int(replacement["access_expires_at"]),
                        refresh_expires_at=int(
                            replacement["next_refresh_expires_at"]
                        ),
                    )
                db.execute(
                    "UPDATE auth_sessions SET revoked_at=?,revoke_reason='refresh_replay' "
                    "WHERE id=? AND revoked_at IS NULL",
                    (now, session_id),
                )
                return RefreshRecord("replayed")
            if (
                row["revoked_at"] is not None
                or int(row["refresh_expires_at"]) <= now
                or int(row["absolute_expires_at"]) <= now
            ):
                prune_session_token_family(db, session_id, now)
                prune_expired_tokens(db, now)
                return RefreshRecord("expired")
            if row["status"] != "active":
                return RefreshRecord("unavailable")
            session_expires_at = int(row["absolute_expires_at"])
            access_expires_at = min(access_expires_at, session_expires_at)
            refresh_expires_at = min(refresh_expires_at, session_expires_at)
            db.execute(
                "UPDATE auth_refresh_tokens SET consumed_at=?,refresh_request_id=?,"
                "replacement_digest=?,replacement_access_digest=? "
                "WHERE token_digest=? AND consumed_at IS NULL",
                (
                    now,
                    request_id,
                    refresh_digest,
                    access_digest,
                    old_digest,
                ),
            )
            _insert_tokens(
                db,
                session_id=session_id,
                access_digest=access_digest,
                access_nonce=access_nonce,
                access_expires_at=access_expires_at,
                refresh_digest=refresh_digest,
                refresh_nonce=refresh_nonce,
                refresh_expires_at=refresh_expires_at,
                now=now,
            )
            prune_session_token_family(db, session_id, now)
            prune_expired_tokens(db, now)
            db.execute(
                "UPDATE auth_sessions SET last_seen_at=? WHERE id=?",
                (now, session_id),
            )
            return RefreshRecord(
                state="rotated",
                account=_account(row),
                session_id=session_id,
                session_expires_at=session_expires_at,
                access_nonce=access_nonce,
                refresh_nonce=refresh_nonce,
                access_expires_at=access_expires_at,
                refresh_expires_at=refresh_expires_at,
            )

    def revoke_session_by_access(self, digest: bytes, now: int) -> None:
        with self._lock, closing(self.connect()) as db, db:
            db.execute(
                "UPDATE auth_sessions SET revoked_at=?,revoke_reason='logout' "
                "WHERE id=(SELECT session_id FROM auth_access_tokens "
                "WHERE token_digest=?) AND revoked_at IS NULL",
                (now, digest),
            )

    def set_account_status(self, account_id: str, status: str, now: int) -> None:
        if status not in {"active", "suspended", "deleting"}:
            raise ValueError("invalid account status")
        with self._lock, closing(self.connect()) as db, db:
            db.execute(
                "UPDATE accounts SET status=?,updated_at=? WHERE id=?",
                (status, now, account_id),
            )
            if status != "active":
                db.execute(
                    "UPDATE auth_sessions SET revoked_at=?,revoke_reason='account_status' "
                    "WHERE account_id=? AND revoked_at IS NULL",
                    (now, account_id),
                )

    def ping(self) -> bool:
        try:
            metadata = self.path.lstat()
            if self.path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
                return False
            uri = self.path.absolute().as_uri() + "?mode=rw"
            with closing(
                sqlite3.connect(uri, uri=True, timeout=15)
            ) as database:
                database.execute("PRAGMA busy_timeout=15000")
                required_tables = set(_REQUIRED_AUTH_SCHEMA)
                placeholders = ",".join("?" for _ in required_tables)
                actual_tables = {
                    str(row[0])
                    for row in database.execute(
                        "SELECT name FROM sqlite_schema WHERE type='table' "
                        f"AND name IN ({placeholders})",
                        tuple(required_tables),
                    )
                }
                if actual_tables != required_tables:
                    return False
                version = database.execute(
                    "SELECT COALESCE(MAX(version),0) "
                    "FROM auth_schema_migrations"
                ).fetchone()[0]
                if int(version) != SUPPORTED_AUTH_SCHEMA_VERSION:
                    return False
                for table, required_columns in _REQUIRED_AUTH_SCHEMA.items():
                    columns = {
                        str(row[1])
                        for row in database.execute(f"PRAGMA table_info({table})")
                    }
                    if not required_columns.issubset(columns):
                        return False
                # Readiness must prove that the live process can acquire the
                # SQLite write path (including WAL/shm creation), not merely
                # read an old file. BEGIN IMMEDIATE changes no application
                # data and the explicit rollback leaves no durable mutation.
                database.execute("BEGIN IMMEDIATE")
                database.rollback()
                return True
        except (OSError, sqlite3.Error, TypeError, ValueError):
            return False


def _insert_account(
    db: sqlite3.Connection,
    account: Account,
    *,
    password_hash: str,
    now: int,
) -> None:
    db.execute(
        "INSERT INTO accounts"
        "(id,email,display_name,password_hash,status,created_at,updated_at) "
        "VALUES(?,?,?,?,?,?,?)",
        (
            account.id,
            account.email,
            account.display_name,
            password_hash,
            account.status,
            now,
            now,
        ),
    )


def _insert_session(
    db: sqlite3.Connection,
    *,
    session_id: str,
    account_id: str,
    installation_id: str,
    session_expires_at: int,
    now: int,
) -> None:
    db.execute(
        "INSERT INTO auth_sessions"
        "(id,account_id,installation_id,created_at,last_seen_at,"
        "absolute_expires_at) VALUES(?,?,?,?,?,?)",
        (
            session_id,
            account_id,
            installation_id,
            now,
            now,
            session_expires_at,
        ),
    )


def _insert_tokens(
    db: sqlite3.Connection,
    *,
    session_id: str,
    access_digest: bytes,
    access_nonce: bytes,
    access_expires_at: int,
    refresh_digest: bytes,
    refresh_nonce: bytes,
    refresh_expires_at: int,
    now: int,
) -> None:
    db.execute(
        "INSERT INTO auth_access_tokens"
        "(token_digest,token_nonce,session_id,created_at,expires_at) "
        "VALUES(?,?,?,?,?)",
        (access_digest, access_nonce, session_id, now, access_expires_at),
    )
    db.execute(
        "INSERT INTO auth_refresh_tokens"
        "(token_digest,token_nonce,session_id,created_at,expires_at) "
        "VALUES(?,?,?,?,?)",
        (refresh_digest, refresh_nonce, session_id, now, refresh_expires_at),
    )


def _account(row: sqlite3.Row) -> Account:
    return Account(
        id=str(row["id"]),
        email=str(row["email"]),
        display_name=str(row["display_name"]),
        status=str(row["status"]),
        email_verified_at=row["email_verified_at"],
    )
