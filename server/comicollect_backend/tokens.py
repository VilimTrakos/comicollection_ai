"""Reconstructable opaque tokens without plaintext token persistence."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from dataclasses import dataclass


@dataclass(frozen=True)
class OpaqueToken:
    raw: str
    nonce: bytes
    digest: bytes


class OpaqueTokenCodec:
    def __init__(self, key: bytes):
        if len(key) < 32:
            raise ValueError("token key must contain at least 32 bytes")
        self._key = hmac.new(key, b"comicollect-token-v1", hashlib.sha256).digest()

    @property
    def key_fingerprint(self) -> bytes:
        return hashlib.sha256(self._key).digest()

    def create(self, prefix: str) -> OpaqueToken:
        return self.from_nonce(prefix, secrets.token_bytes(32))

    def from_nonce(self, prefix: str, nonce: bytes) -> OpaqueToken:
        if prefix not in {"cca_", "ccr_"} or len(nonce) != 32:
            raise ValueError("invalid token material")
        mac = hmac.new(
            self._key,
            prefix.encode("ascii") + b"\0" + nonce,
            hashlib.sha256,
        ).digest()
        raw = prefix + _encode(nonce) + "." + _encode(mac)
        return OpaqueToken(raw, bytes(nonce), digest_token(raw))


def digest_token(token: str) -> bytes:
    if not isinstance(token, str) or not token.isascii():
        raise ValueError("invalid token")
    return hashlib.sha256(token.encode("ascii")).digest()


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")
