"""Transactional persistence for email verification and password reset."""

from __future__ import annotations

import hmac
import sqlite3
from dataclasses import dataclass

from .action_tokens import EMAIL_VERIFICATION, PASSWORD_RESET
from .auth_models import Account
from .auth_repository import AuthRepository


_RETENTION_GRACE_MS = 7 * 24 * 60 * 60 * 1000


@dataclass(frozen=True)
class ActionResult:
    state: str
    account: Account | None = None


class AuthActionRepository:
    def __init__(self, repository: AuthRepository):
        self.repository = repository

    def issue_for_account(
        self,
        *,
        account_id: str,
        purpose: str,
        token_digest: bytes,
        token_nonce: bytes,
        expires_at: int,
        now: int,
    ) -> Account | None:
        with self.repository.write_transaction() as database:
            row = database.execute(
                "SELECT * FROM accounts WHERE id=? AND status='active'",
                (account_id,),
            ).fetchone()
            if row is None:
                return None
            if purpose == EMAIL_VERIFICATION and row["email_verified_at"] is not None:
                return None
            _issue(
                database,
                account_id=account_id,
                purpose=purpose,
                token_digest=token_digest,
                token_nonce=token_nonce,
                expires_at=expires_at,
                now=now,
            )
            return _account(row)

    def issue_for_email(
        self,
        *,
        email: str,
        purpose: str,
        token_digest: bytes,
        token_nonce: bytes,
        expires_at: int,
        now: int,
    ) -> Account | None:
        with self.repository.write_transaction() as database:
            row = database.execute(
                "SELECT * FROM accounts WHERE email=? AND status='active'",
                (email,),
            ).fetchone()
            if row is None:
                _prune(database, now)
                return None
            account = _account(row)
            _issue(
                database,
                account_id=account.id,
                purpose=purpose,
                token_digest=token_digest,
                token_nonce=token_nonce,
                expires_at=expires_at,
                now=now,
            )
            return account

    def confirm_email(
        self,
        *,
        token_digest: bytes,
        account_id: str,
        request_id: str,
        payload_digest: bytes,
        now: int,
    ) -> ActionResult:
        with self.repository.write_transaction() as database:
            row = _action(database, token_digest, EMAIL_VERIFICATION)
            state = _state(
                row,
                account_id=account_id,
                request_id=request_id,
                payload_digest=payload_digest,
                now=now,
            )
            if state == "duplicate":
                return ActionResult(state, _account(row))
            if state != "active":
                return ActionResult(state)
            database.execute(
                "UPDATE accounts SET email_verified_at=COALESCE(email_verified_at,?),"
                "updated_at=? WHERE id=?",
                (now, now, account_id),
            )
            _mark_consumed(
                database,
                token_digest=token_digest,
                request_id=request_id,
                payload_digest=payload_digest,
                now=now,
            )
            verified = database.execute(
                "SELECT * FROM accounts WHERE id=?",
                (account_id,),
            ).fetchone()
            return ActionResult("consumed", _account(verified))

    def confirm_password_reset(
        self,
        *,
        token_digest: bytes,
        request_id: str,
        payload_digest: bytes,
        password_hash: str,
        now: int,
    ) -> ActionResult:
        with self.repository.write_transaction() as database:
            row = _action(database, token_digest, PASSWORD_RESET)
            state = _state(
                row,
                account_id=None,
                request_id=request_id,
                payload_digest=payload_digest,
                now=now,
            )
            if state == "duplicate":
                return ActionResult(state, _account(row))
            if state != "active":
                return ActionResult(state)
            account = _account(row)
            database.execute(
                "UPDATE accounts SET password_hash=?,updated_at=? WHERE id=?",
                (password_hash, now, account.id),
            )
            database.execute(
                "UPDATE auth_sessions SET revoked_at=?,revoke_reason='password_reset' "
                "WHERE account_id=? AND revoked_at IS NULL",
                (now, account.id),
            )
            database.execute(
                "DELETE FROM auth_access_tokens WHERE session_id IN "
                "(SELECT id FROM auth_sessions WHERE account_id=?)",
                (account.id,),
            )
            database.execute(
                "DELETE FROM auth_refresh_tokens WHERE session_id IN "
                "(SELECT id FROM auth_sessions WHERE account_id=?)",
                (account.id,),
            )
            _mark_consumed(
                database,
                token_digest=token_digest,
                request_id=request_id,
                payload_digest=payload_digest,
                now=now,
            )
            database.execute(
                "UPDATE auth_action_tokens SET superseded_at=? "
                "WHERE account_id=? AND purpose=? AND token_digest<>? "
                "AND consumed_at IS NULL AND superseded_at IS NULL",
                (now, account.id, PASSWORD_RESET, token_digest),
            )
            return ActionResult("consumed", account)


def _issue(
    database: sqlite3.Connection,
    *,
    account_id: str,
    purpose: str,
    token_digest: bytes,
    token_nonce: bytes,
    expires_at: int,
    now: int,
) -> None:
    if purpose not in {EMAIL_VERIFICATION, PASSWORD_RESET}:
        raise ValueError("unsupported action token purpose")
    _prune(database, now)
    database.execute(
        "UPDATE auth_action_tokens SET superseded_at=? "
        "WHERE account_id=? AND purpose=? AND consumed_at IS NULL "
        "AND superseded_at IS NULL",
        (now, account_id, purpose),
    )
    database.execute(
        "INSERT INTO auth_action_tokens"
        "(token_digest,token_nonce,account_id,purpose,created_at,expires_at) "
        "VALUES(?,?,?,?,?,?)",
        (
            token_digest,
            token_nonce,
            account_id,
            purpose,
            now,
            expires_at,
        ),
    )


def _action(
    database: sqlite3.Connection,
    token_digest: bytes,
    purpose: str,
) -> sqlite3.Row | None:
    return database.execute(
        "SELECT a.*,t.token_digest,t.purpose,t.expires_at,t.superseded_at,"
        "t.consumed_at,t.consume_request_id,t.consume_payload_digest "
        "FROM auth_action_tokens t JOIN accounts a ON a.id=t.account_id "
        "WHERE t.token_digest=? AND t.purpose=?",
        (token_digest, purpose),
    ).fetchone()


def _state(
    row: sqlite3.Row | None,
    *,
    account_id: str | None,
    request_id: str,
    payload_digest: bytes,
    now: int,
) -> str:
    if row is None or (account_id is not None and row["id"] != account_id):
        return "invalid"
    if row["consumed_at"] is not None:
        stored_digest = row["consume_payload_digest"]
        if (
            row["consume_request_id"] == request_id
            and stored_digest is not None
            and hmac.compare_digest(bytes(stored_digest), payload_digest)
        ):
            return "duplicate"
        return "invalid"
    if row["superseded_at"] is not None:
        return "invalid"
    if int(row["expires_at"]) <= now:
        return "expired"
    if row["status"] != "active":
        return "unavailable"
    return "active"


def _mark_consumed(
    database: sqlite3.Connection,
    *,
    token_digest: bytes,
    request_id: str,
    payload_digest: bytes,
    now: int,
) -> None:
    database.execute(
        "UPDATE auth_action_tokens SET consumed_at=?,consume_request_id=?,"
        "consume_payload_digest=? WHERE token_digest=? AND consumed_at IS NULL",
        (now, request_id, payload_digest, token_digest),
    )


def _prune(database: sqlite3.Connection, now: int) -> None:
    database.execute(
        "DELETE FROM auth_action_tokens WHERE expires_at<?",
        (now - _RETENTION_GRACE_MS,),
    )


def _account(row: sqlite3.Row) -> Account:
    return Account(
        id=str(row["id"]),
        email=str(row["email"]),
        display_name=str(row["display_name"]),
        status=str(row["status"]),
        email_verified_at=row["email_verified_at"],
    )
