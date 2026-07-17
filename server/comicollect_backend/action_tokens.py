"""Purpose-bound, reconstructable tokens for short-lived account actions."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from dataclasses import dataclass


EMAIL_VERIFICATION = "email_verification"
PASSWORD_RESET = "password_reset"
_PREFIXES = {
    EMAIL_VERIFICATION: "cce_",
    PASSWORD_RESET: "ccp_",
}


@dataclass(frozen=True)
class ActionToken:
    raw: str
    nonce: bytes
    digest: bytes


class ActionTokenCodec:
    def __init__(self, key: bytes):
        if len(key) < 32:
            raise ValueError("action token key must contain at least 32 bytes")
        self._key = hmac.new(
            key,
            b"comicollect-action-token-v1",
            hashlib.sha256,
        ).digest()

    def create(self, purpose: str) -> ActionToken:
        return self.from_nonce(purpose, secrets.token_bytes(32))

    def from_nonce(self, purpose: str, nonce: bytes) -> ActionToken:
        prefix = _prefix(purpose)
        if len(nonce) != 32:
            raise ValueError("invalid action token nonce")
        mac = hmac.new(
            self._purpose_key(purpose),
            prefix.encode("ascii") + b"\0" + nonce,
            hashlib.sha256,
        ).digest()
        raw = prefix + _encode(nonce) + "." + _encode(mac)
        return ActionToken(raw, bytes(nonce), _digest(raw))

    def digest(self, purpose: str, raw: str) -> bytes:
        prefix = _prefix(purpose)
        if not isinstance(raw, str) or not raw.startswith(prefix) or not raw.isascii():
            raise ValueError("invalid action token")
        encoded = raw[len(prefix) :].split(".")
        if len(encoded) != 2:
            raise ValueError("invalid action token")
        nonce, supplied_mac = _decode(encoded[0]), _decode(encoded[1])
        expected = self.from_nonce(purpose, nonce)
        expected_mac = _decode(expected.raw.rsplit(".", 1)[1])
        if len(supplied_mac) != 32 or not hmac.compare_digest(
            supplied_mac,
            expected_mac,
        ):
            raise ValueError("invalid action token")
        return _digest(raw)

    def payload_digest(self, purpose: str, request_id: str, payload: str) -> bytes:
        if not isinstance(request_id, str) or not isinstance(payload, str):
            raise TypeError("action confirmation values must be text")
        return hmac.new(
            self._purpose_key(purpose),
            b"confirm\0"
            + request_id.encode("utf-8")
            + b"\0"
            + payload.encode("utf-8"),
            hashlib.sha256,
        ).digest()

    def _purpose_key(self, purpose: str) -> bytes:
        _prefix(purpose)
        return hmac.new(
            self._key,
            b"purpose\0" + purpose.encode("ascii"),
            hashlib.sha256,
        ).digest()


def _prefix(purpose: str) -> str:
    try:
        return _PREFIXES[purpose]
    except (KeyError, TypeError) as error:
        raise ValueError("unsupported action token purpose") from error


def _digest(raw: str) -> bytes:
    return hashlib.sha256(raw.encode("ascii")).digest()


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    decoded = base64.b64decode(value + padding, altchars=b"-_", validate=True)
    # Reject alternate/non-canonical encodings whose ignored trailing bits
    # decode to the same bytes. Otherwise a token can be textually modified
    # while retaining a valid MAC and digest identity.
    if _encode(decoded) != value:
        raise ValueError("invalid action token encoding")
    return decoded
