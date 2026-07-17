"""Explicit exceptions which are safe to serialize across the HTTP boundary."""

from __future__ import annotations


class PublicApiError(Exception):
    """Expected API failure with a stable, deliberately public message."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        headers: dict[str, str] | None = None,
    ):
        super().__init__(message)
        self.status = int(status)
        self.code = str(code)
        self.headers = dict(headers or {})
