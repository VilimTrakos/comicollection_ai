"""Account registration and rotating session credentials."""

from __future__ import annotations

import re
import time
import unicodedata
from http import HTTPStatus
from typing import Callable

from .auth_models import AuthContext, AuthError, TokenPair
from .auth_repository import AuthRepository, DuplicateEmailError
from .passwords import PasswordHasher
from .rate_limit import RateLimiter, RatePolicy
from .tokens import OpaqueTokenCodec, digest_token

_OPAQUE_ID_RE = re.compile(r"^[A-Za-z0-9._-]{8,128}$")


class AuthService:
    def __init__(
        self,
        repository: AuthRepository,
        hasher: PasswordHasher,
        *,
        clock: Callable[[], int] | None = None,
        token_key: bytes | None = None,
        rate_limiter: RateLimiter | None = None,
        registration_enabled: bool = False,
        access_ttl_ms: int = 15 * 60 * 1000,
        refresh_ttl_ms: int = 30 * 24 * 60 * 60 * 1000,
        session_ttl_ms: int = 90 * 24 * 60 * 60 * 1000,
    ):
        if not 0 < access_ttl_ms < refresh_ttl_ms <= session_ttl_ms:
            raise ValueError("invalid session lifetimes")
        self.repository = repository
        self.hasher = hasher
        self.clock = clock or (lambda: int(time.time() * 1000))
        self.tokens = OpaqueTokenCodec(token_key or hasher.pepper)
        self.repository.bind_token_key(self.tokens.key_fingerprint)
        self.registration_enabled = registration_enabled
        self.access_ttl_ms = access_ttl_ms
        self.refresh_ttl_ms = refresh_ttl_ms
        self.session_ttl_ms = session_ttl_ms
        self.rate_limiter = rate_limiter or RateLimiter(
            clock=self.clock,
            policies={
                "register": RatePolicy(5, 60 * 60 * 1000),
                "login-ip": RatePolicy(100, 60_000),
                "login-account": RatePolicy(10, 60_000),
                "refresh-ip": RatePolicy(300, 60_000),
                "refresh-session": RatePolicy(10, 60_000),
            },
        )
        self._dummy_hash = self.hasher.hash("not-a-real-password")

    def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
        installation_id: str,
        rate_key: str = "local",
    ) -> dict:
        if not self.registration_enabled:
            raise AuthError(
                HTTPStatus.FORBIDDEN,
                "registration_disabled",
                "Public registration is disabled",
            )
        self.rate_limiter.consume("register", rate_key)
        normalized_email = _email(email)
        normalized_name = _display_name(display_name)
        installation = _installation_id(installation_id)
        try:
            encoded = self.hasher.hash(password)
        except (TypeError, ValueError) as exc:
            raise AuthError(
                HTTPStatus.BAD_REQUEST,
                "password_policy_failed",
                "Password must contain between 12 and 128 characters",
            ) from exc
        now = self.clock()
        try:
            account = self.repository.create_account(
                email=normalized_email,
                display_name=normalized_name,
                password_hash=encoded,
                now=now,
            )
        except DuplicateEmailError as exc:
            raise AuthError(
                HTTPStatus.CONFLICT,
                "email_in_use",
                "An account already exists for this email",
            ) from exc
        pair = self._new_session(account.id, installation, now)
        return {"account": account.public_json(), **pair.json()}

    def login(
        self,
        *,
        email: str,
        password: str,
        installation_id: str,
        rate_key: str = "local",
    ) -> dict:
        self.rate_limiter.consume("login-ip", rate_key)
        try:
            normalized_email = _email(email)
            installation = _installation_id(installation_id)
        except AuthError:
            self.hasher.verify(password if isinstance(password, str) else "", self._dummy_hash)
            raise _invalid_credentials()
        self.rate_limiter.consume("login-account", normalized_email)
        stored = self.repository.account_with_password(normalized_email)
        encoded = self._dummy_hash if stored is None else stored[1]
        verified = self.hasher.verify(password, encoded)
        if stored is None or not verified or stored[0].status != "active":
            raise _invalid_credentials()
        account = stored[0]
        now = self.clock()
        if self.hasher.needs_rehash(encoded):
            self.repository.update_password_hash(account.id, self.hasher.hash(password), now)
        pair = self._new_session(account.id, installation, now)
        return {"account": account.public_json(), **pair.json()}

    def refresh(
        self,
        *,
        refresh_token: str,
        installation_id: str,
        request_id: str,
        rate_key: str = "local",
    ) -> dict:
        self.rate_limiter.consume("refresh-ip", rate_key)
        _installation_id(installation_id)
        normalized_request_id = _request_id(request_id)
        try:
            old_digest = _token_digest(refresh_token, "ccr_")
        except AuthError as exc:
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "invalid_refresh_token",
                "Refresh token is invalid",
            ) from exc
        self.rate_limiter.consume("refresh-session", old_digest.hex())
        now = self.clock()
        access_token = self.tokens.create("cca_")
        next_refresh_token = self.tokens.create("ccr_")
        access_expires = now + self.access_ttl_ms
        refresh_expires = now + self.refresh_ttl_ms
        record = self.repository.rotate_refresh(
            old_digest=old_digest,
            installation_id=installation_id,
            request_id=normalized_request_id,
            access_digest=access_token.digest,
            access_nonce=access_token.nonce,
            access_expires_at=access_expires,
            refresh_digest=next_refresh_token.digest,
            refresh_nonce=next_refresh_token.nonce,
            refresh_expires_at=refresh_expires,
            now=now,
        )
        if record.state == "replayed":
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "refresh_reused",
                "Refresh token reuse revoked this session",
            )
        if record.state == "installation_mismatch":
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "invalid_refresh_token",
                "Refresh token is invalid",
            )
        if record.state == "expired":
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "refresh_expired",
                "Refresh token has expired",
            )
        if record.state == "unavailable":
            raise AuthError(
                HTTPStatus.FORBIDDEN,
                "account_unavailable",
                "Account is unavailable",
            )
        if record.state not in {"rotated", "duplicate"} or record.account is None:
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "invalid_refresh_token",
                "Refresh token is invalid",
            )
        access_token = self.tokens.from_nonce("cca_", record.access_nonce)
        next_refresh_token = self.tokens.from_nonce("ccr_", record.refresh_nonce)
        pair = TokenPair(
            access_token.raw,
            record.access_expires_at,
            next_refresh_token.raw,
            record.refresh_expires_at,
        )
        return {"account": record.account.public_json(), **pair.json()}

    def authenticate_access(self, access_token: str) -> AuthContext:
        digest = _token_digest(access_token, "cca_")
        record = self.repository.authenticate_access(digest, self.clock())
        if record.state == "expired":
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "access_expired",
                "Access token has expired",
            )
        if record.context is None:
            raise AuthError(
                HTTPStatus.UNAUTHORIZED,
                "invalid_token",
                "Access token is invalid or expired",
            )
        return record.context

    def logout(self, access_token: str) -> None:
        digest = _token_digest(access_token, "cca_")
        self.repository.revoke_session_by_access(digest, self.clock())

    def me(self, access_token: str) -> dict:
        return self.authenticate_access(access_token).account.public_json()

    def _new_session(self, account_id: str, installation_id: str, now: int) -> TokenPair:
        access_token = self.tokens.create("cca_")
        refresh_token = self.tokens.create("ccr_")
        access_expires = now + self.access_ttl_ms
        refresh_expires = now + self.refresh_ttl_ms
        self.repository.create_session(
            account_id=account_id,
            installation_id=installation_id,
            access_digest=access_token.digest,
            access_nonce=access_token.nonce,
            access_expires_at=access_expires,
            refresh_digest=refresh_token.digest,
            refresh_nonce=refresh_token.nonce,
            refresh_expires_at=refresh_expires,
            session_expires_at=now + self.session_ttl_ms,
            now=now,
        )
        return TokenPair(
            access_token.raw,
            access_expires,
            refresh_token.raw,
            refresh_expires,
        )


def _email(raw: str) -> str:
    if not isinstance(raw, str):
        raise AuthError(400, "invalid_request", "Email must be text")
    value = unicodedata.normalize("NFKC", raw).strip().casefold()
    if (
        len(value.encode("utf-8")) > 254
        or value.count("@") != 1
        or not value.split("@", 1)[0]
        or "." not in value.split("@", 1)[1]
        or any(ord(character) < 32 for character in value)
    ):
        raise AuthError(400, "invalid_request", "Email is invalid")
    return value


def _display_name(raw: str) -> str:
    if not isinstance(raw, str):
        raise AuthError(400, "invalid_request", "Display name must be text")
    value = unicodedata.normalize("NFKC", raw).strip()
    if not value or len(value) > 100 or len(value.encode("utf-8")) > 200:
        raise AuthError(400, "invalid_request", "Display name is invalid")
    return value


def _installation_id(raw: str) -> str:
    if not isinstance(raw, str) or _OPAQUE_ID_RE.fullmatch(raw) is None:
        raise AuthError(400, "invalid_request", "Installation id is invalid")
    return raw


def _token_digest(token: str, prefix: str) -> bytes:
    if (
        not isinstance(token, str)
        or not token.startswith(prefix)
        or not 80 <= len(token) <= 128
        or not token.isascii()
    ):
        raise AuthError(401, "invalid_token", "Token is invalid")
    return digest_token(token)


def _request_id(raw: str) -> str:
    if not isinstance(raw, str) or _OPAQUE_ID_RE.fullmatch(raw) is None:
        raise AuthError(400, "invalid_request", "Request id is invalid")
    return raw


def _invalid_credentials() -> AuthError:
    return AuthError(401, "invalid_credentials", "Email or password is incorrect")
