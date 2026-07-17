"""Email verification and password-reset orchestration."""

from __future__ import annotations

import logging
import re
import unicodedata
from http import HTTPStatus
from typing import Callable

from .action_tokens import (
    EMAIL_VERIFICATION,
    PASSWORD_RESET,
    ActionToken,
    ActionTokenCodec,
)
from .auth_action_repository import ActionResult, AuthActionRepository
from .auth_models import Account, AuthContext, AuthError
from .email_delivery import EmailSender, OutboundEmail
from .passwords import PasswordHasher
from .rate_limit import RateLimiter


LOG = logging.getLogger("comicollect.account_actions")
_OPAQUE_ID = re.compile(r"^[A-Za-z0-9._-]{8,128}$")


class AccountActionService:
    def __init__(
        self,
        repository: AuthActionRepository,
        hasher: PasswordHasher,
        *,
        token_key: bytes,
        rate_limiter: RateLimiter,
        clock: Callable[[], int],
        email_sender: EmailSender | None = None,
        email_verification_ttl_ms: int = 24 * 60 * 60 * 1000,
        password_reset_ttl_ms: int = 60 * 60 * 1000,
    ):
        if min(email_verification_ttl_ms, password_reset_ttl_ms) <= 0:
            raise ValueError("account action lifetimes must be positive")
        self.repository = repository
        self.hasher = hasher
        self.tokens = ActionTokenCodec(token_key)
        self.rate_limiter = rate_limiter
        self.clock = clock
        self.email_sender = email_sender
        self.email_verification_ttl_ms = email_verification_ttl_ms
        self.password_reset_ttl_ms = password_reset_ttl_ms

    def request_email_verification(
        self,
        context: AuthContext,
        *,
        rate_key: str,
    ) -> None:
        self.rate_limiter.consume("email-verification-ip", rate_key)
        self.rate_limiter.consume("email-verification-account", context.account_id)
        if self.email_sender is None:
            return
        now = self.clock()
        token = self.tokens.create(EMAIL_VERIFICATION)
        account = self.repository.issue_for_account(
            account_id=context.account_id,
            purpose=EMAIL_VERIFICATION,
            token_digest=token.digest,
            token_nonce=token.nonce,
            expires_at=now + self.email_verification_ttl_ms,
            now=now,
        )
        if account is not None:
            self._deliver(account, token, EMAIL_VERIFICATION)

    def confirm_email_verification(
        self,
        context: AuthContext,
        *,
        token: str,
        request_id: str,
        rate_key: str,
    ) -> Account:
        self.rate_limiter.consume("action-confirm-ip", rate_key)
        normalized_request_id = _request_id(request_id)
        digest = _token_digest(self.tokens, EMAIL_VERIFICATION, token)
        payload_digest = self.tokens.payload_digest(
            EMAIL_VERIFICATION,
            normalized_request_id,
            "",
        )
        result = self.repository.confirm_email(
            token_digest=digest,
            account_id=context.account_id,
            request_id=normalized_request_id,
            payload_digest=payload_digest,
            now=self.clock(),
        )
        return _account_or_error(result)

    def request_password_reset(self, email: object, *, rate_key: str) -> None:
        self.rate_limiter.consume("password-reset-ip", rate_key)
        normalized_email = _reset_email(email)
        self.rate_limiter.consume("password-reset-account", normalized_email)
        if self.email_sender is None or not _looks_like_email(normalized_email):
            return
        now = self.clock()
        token = self.tokens.create(PASSWORD_RESET)
        account = self.repository.issue_for_email(
            email=normalized_email,
            purpose=PASSWORD_RESET,
            token_digest=token.digest,
            token_nonce=token.nonce,
            expires_at=now + self.password_reset_ttl_ms,
            now=now,
        )
        if account is not None:
            self._deliver(account, token, PASSWORD_RESET)

    def confirm_password_reset(
        self,
        *,
        token: str,
        new_password: str,
        request_id: str,
        rate_key: str,
    ) -> None:
        self.rate_limiter.consume("action-confirm-ip", rate_key)
        normalized_request_id = _request_id(request_id)
        digest = _token_digest(self.tokens, PASSWORD_RESET, token)
        try:
            password_hash = self.hasher.hash(new_password)
        except (TypeError, ValueError) as error:
            raise AuthError(
                HTTPStatus.BAD_REQUEST,
                "password_policy_failed",
                "Password must contain between 12 and 128 characters",
            ) from error
        payload_digest = self.tokens.payload_digest(
            PASSWORD_RESET,
            normalized_request_id,
            new_password,
        )
        result = self.repository.confirm_password_reset(
            token_digest=digest,
            request_id=normalized_request_id,
            payload_digest=payload_digest,
            password_hash=password_hash,
            now=self.clock(),
        )
        _account_or_error(result)

    def _deliver(self, account: Account, token: ActionToken, purpose: str) -> None:
        try:
            self.email_sender.send(_message(account, token, purpose))
        except Exception as error:
            # Reset requests must not reveal whether the address exists. The
            # request remains accepted and a later request supersedes this token.
            LOG.error(
                "account action email failed; purpose=%s exception=%s",
                purpose,
                type(error).__name__,
            )


def _message(account: Account, token: ActionToken, purpose: str) -> OutboundEmail:
    verification = purpose == EMAIL_VERIFICATION
    subject = "Confirm your Comicollect email" if verification else "Reset your Comicollect password"
    action = "verify your email" if verification else "reset your password"
    return OutboundEmail(
        message_id=f"<{purpose}-{token.digest.hex()}@comicollect.invalid>",
        recipient=account.email,
        subject=subject,
        text_body=(
            f"Hello {account.display_name},\n\n"
            f"Use this one-time token to {action}:\n\n{token.raw}\n\n"
            "If you did not request this action, you can ignore this message."
        ),
    )


def _token_digest(codec: ActionTokenCodec, purpose: str, token: str) -> bytes:
    try:
        return codec.digest(purpose, token)
    except (TypeError, ValueError) as error:
        raise AuthError(400, "action_token_invalid", "Action token is invalid") from error


def _account_or_error(result: ActionResult) -> Account:
    if result.state in {"consumed", "duplicate"} and result.account is not None:
        return result.account
    # Keep every token failure indistinguishable. In particular, callers must
    # not be able to infer whether a token existed, expired, was superseded, or
    # belonged to an account that has since been disabled.
    raise AuthError(400, "action_token_invalid", "Action token is invalid")


def _request_id(raw: object) -> str:
    if not isinstance(raw, str) or _OPAQUE_ID.fullmatch(raw) is None:
        raise AuthError(400, "invalid_request", "Request id is invalid")
    return raw


def _reset_email(raw: object) -> str:
    if not isinstance(raw, str):
        raise AuthError(400, "invalid_request", "Email must be text")
    return unicodedata.normalize("NFKC", raw).strip().casefold()


def _looks_like_email(value: str) -> bool:
    return (
        len(value.encode("utf-8")) <= 254
        and value.count("@") == 1
        and bool(value.split("@", 1)[0])
        and "." in value.split("@", 1)[1]
        and not any(
            character.isspace()
            or ord(character) < 32
            or ord(character) == 127
            for character in value
        )
    )
