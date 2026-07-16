"""Versioned stdlib scrypt password hashing."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from dataclasses import dataclass


MAX_SCRYPT_N = 131_072
MAX_SCRYPT_R = 8
MAX_SCRYPT_P = 8
MAX_SCRYPT_DKLEN = 64
MAX_SCRYPT_MAXMEM = 256 * 1024 * 1024


@dataclass(frozen=True)
class ScryptParams:
    n: int = 32768
    r: int = 8
    p: int = 3
    dklen: int = 32
    maxmem: int = 128 * 1024 * 1024

    def validate(self, *, production: bool = False) -> None:
        if self.n < 2 or self.n & (self.n - 1):
            raise ValueError("scrypt n must be a power of two")
        if min(self.r, self.p, self.dklen) <= 0:
            raise ValueError("scrypt parameters must be positive")
        maximums = (
            ("n", self.n, MAX_SCRYPT_N),
            ("r", self.r, MAX_SCRYPT_R),
            ("p", self.p, MAX_SCRYPT_P),
            ("dklen", self.dklen, MAX_SCRYPT_DKLEN),
            ("maxmem", self.maxmem, MAX_SCRYPT_MAXMEM),
        )
        for name, value, maximum in maximums:
            if value > maximum:
                raise ValueError(
                    f"scrypt {name} exceeds the safe maximum of {maximum}"
                )
        if self.maxmem <= 0:
            raise ValueError("scrypt maxmem must be positive and bounded")
        required_memory = 128 * self.n * self.r
        if self.maxmem and self.maxmem <= required_memory:
            raise ValueError("scrypt maxmem is too small")
        if production and not _owasp_strength(self):
            raise ValueError("scrypt parameters are below the production minimum")


def _owasp_strength(value: ScryptParams) -> bool:
    """Accept the OWASP scrypt cost combinations or anything stronger."""
    if value.r < 8 or value.dklen < 32:
        return False
    return (
        value.n >= 131072
        or (value.n >= 65536 and value.p >= 2)
        or (value.n >= 32768 and value.p >= 3)
        or (value.n >= 16384 and value.p >= 5)
    )


class PasswordHasher:
    _prefix = "cc-scrypt-v1"

    def __init__(self, pepper: bytes, params: ScryptParams | None = None):
        if len(pepper) < 32:
            raise ValueError("password pepper must contain at least 32 bytes")
        self.pepper = bytes(pepper)
        self.params = params or ScryptParams()
        self.params.validate()

    def hash(self, password: str) -> str:
        password_bytes = _password_bytes(password, enforce_policy=True)
        salt = secrets.token_bytes(16)
        digest = self._derive(password_bytes, salt, self.params)
        encoded_salt = _encode(salt)
        encoded_digest = _encode(digest)
        p = self.params
        return f"{self._prefix}${p.n}${p.r}${p.p}${p.dklen}${encoded_salt}${encoded_digest}"

    def verify(self, password: str, encoded: str) -> bool:
        try:
            password_bytes = _password_bytes(password, enforce_policy=False)
            params, salt, expected = self._parse(encoded)
            actual = self._derive(password_bytes, salt, params)
            return hmac.compare_digest(actual, expected)
        except (TypeError, ValueError, OverflowError):
            return False

    def needs_rehash(self, encoded: str) -> bool:
        try:
            params, _, _ = self._parse(encoded)
        except (TypeError, ValueError):
            return True
        # maxmem is only a local safety ceiling and is intentionally not part
        # of the encoded hash. Changing that ceiling must not trigger a
        # password rewrite on every login.
        return _cost(params) != _cost(self.params)

    def _derive(self, password: bytes, salt: bytes, params: ScryptParams) -> bytes:
        prepared = hmac.new(self.pepper, password, hashlib.sha256).digest()
        return hashlib.scrypt(
            prepared,
            salt=salt,
            n=params.n,
            r=params.r,
            p=params.p,
            dklen=params.dklen,
            maxmem=params.maxmem,
        )

    @classmethod
    def _parse(cls, encoded: str) -> tuple[ScryptParams, bytes, bytes]:
        parts = encoded.split("$")
        if len(parts) != 7 or parts[0] != cls._prefix:
            raise ValueError("unsupported password hash")
        n, r, p, dklen = map(int, parts[1:5])
        required_memory = 128 * n * r
        params = ScryptParams(
            n=n,
            r=r,
            p=p,
            dklen=dklen,
            # maxmem does not alter the derived value and is not encoded. Use
            # a bounded verification ceiling that can handle every supported
            # cost, including the maximum N=131072/r=8 profile.
            maxmem=max(ScryptParams().maxmem, required_memory * 2),
        )
        params.validate()
        salt, digest = _decode(parts[5]), _decode(parts[6])
        if len(salt) < 16 or len(digest) != params.dklen:
            raise ValueError("invalid password hash")
        return params, salt, digest


def _password_bytes(password: str, *, enforce_policy: bool) -> bytes:
    if not isinstance(password, str):
        raise TypeError("password must be text")
    encoded = password.encode("utf-8")
    if not encoded or len(encoded) > 1024:
        raise ValueError("password has an invalid size")
    if enforce_policy and (len(password) < 12 or len(password) > 128):
        raise ValueError("password must contain between 12 and 128 characters")
    return encoded


def _cost(params: ScryptParams) -> tuple[int, int, int, int]:
    return params.n, params.r, params.p, params.dklen


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.b64decode(value + padding, altchars=b"-_", validate=True)
