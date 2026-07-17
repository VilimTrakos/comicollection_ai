"""Small immutable values shared by authentication modules."""

from __future__ import annotations

from dataclasses import dataclass

from .api_errors import PublicApiError


class AuthError(PublicApiError):
    """Expected authentication failure with a stable API code."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        headers: dict[str, str] | None = None,
    ):
        super().__init__(status, code, message, headers=headers)


@dataclass(frozen=True)
class Account:
    id: str
    email: str
    display_name: str
    status: str
    email_verified_at: int | None
    email_verification_required: bool

    def public_json(self) -> dict:
        return {
            "id": self.id,
            "email": self.email,
            "display_name": self.display_name,
            "email_verified": self.email_verified_at is not None,
        }


@dataclass(frozen=True)
class AuthContext:
    account: Account
    session_id: str

    @property
    def account_id(self) -> str:
        return self.account.id


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    access_expires_at: int
    refresh_token: str
    refresh_expires_at: int

    def json(self) -> dict:
        return {
            "access_token": self.access_token,
            "access_expires_at": self.access_expires_at,
            "refresh_token": self.refresh_token,
            "refresh_expires_at": self.refresh_expires_at,
        }


@dataclass(frozen=True)
class RefreshRecord:
    state: str
    account: Account | None = None
    session_id: str = ""
    session_expires_at: int = 0
    access_nonce: bytes = b""
    refresh_nonce: bytes = b""
    access_expires_at: int = 0
    refresh_expires_at: int = 0


@dataclass(frozen=True)
class AccessRecord:
    state: str
    context: AuthContext | None = None
