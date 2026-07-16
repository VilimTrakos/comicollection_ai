"""Bounded WSGI request parsing and trusted proxy identity."""

from __future__ import annotations

import io
import ipaddress
from http import HTTPStatus
from typing import Iterable, Mapping

from .production_api import MAX_AUTH_BODY, MAX_SYNC_BODY, MAX_V1_SYNC_BODY


class RequestBodyError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def read_body(environ: Mapping[str, object], path: str) -> bytes:
    maximum = {
        "/api/v1/sync": MAX_V1_SYNC_BODY,
        "/api/v2/sync": MAX_SYNC_BODY,
    }.get(path, MAX_AUTH_BODY)
    stream = environ.get("wsgi.input")
    if stream is None:
        stream = io.BytesIO()
    if not hasattr(stream, "read"):
        raise RequestBodyError(400, "invalid_body", "Request body is invalid")

    raw_length = environ.get("CONTENT_LENGTH")
    if raw_length in {None, ""}:
        if not environ.get("wsgi.input_terminated"):
            return b""
        return _read_to_eof(stream, maximum)

    raw_length = str(raw_length)
    if not raw_length or not raw_length.isascii() or not raw_length.isdecimal():
        raise RequestBodyError(
            400,
            "invalid_content_length",
            "Content-Length is invalid",
        )
    try:
        length = int(raw_length)
    except ValueError as error:
        raise RequestBodyError(
            400,
            "invalid_content_length",
            "Content-Length is invalid",
        ) from error
    if length > maximum:
        raise _too_large()

    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = stream.read(remaining)
        if (
            not isinstance(chunk, bytes)
            or not chunk
            or len(chunk) > remaining
        ):
            raise RequestBodyError(
                400,
                "invalid_body",
                "Request body ended before Content-Length",
            )
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def request_headers(environ: Mapping[str, object]) -> dict[str, str]:
    headers = {
        str(key)[5:].replace("_", "-").title(): str(value)
        for key, value in environ.items()
        if str(key).startswith("HTTP_")
    }
    if environ.get("CONTENT_TYPE") not in {None, ""}:
        headers["Content-Type"] = str(environ["CONTENT_TYPE"])
    if environ.get("CONTENT_LENGTH") not in {None, ""}:
        headers["Content-Length"] = str(environ["CONTENT_LENGTH"])
    return headers


def normalized_proxy_addresses(values: Iterable[str]) -> frozenset[str]:
    return frozenset(_required_ip(value) for value in values)


def client_key(
    environ: Mapping[str, object],
    headers: Mapping[str, str],
    trusted_proxy_addresses: frozenset[str],
) -> str:
    peer = _optional_ip(environ.get("REMOTE_ADDR"))
    if peer in trusted_proxy_addresses:
        forwarded = _optional_ip(header(headers, "X-Real-IP"))
        if forwarded is not None:
            return forwarded
    return peer or "unknown"


def header(headers: Mapping[str, str], name: str) -> str | None:
    expected = name.lower()
    return next(
        (value for key, value in headers.items() if key.lower() == expected),
        None,
    )


def _read_to_eof(stream: object, maximum: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = stream.read(min(64 * 1024, maximum + 1 - total))
        if not isinstance(chunk, bytes):
            raise RequestBodyError(400, "invalid_body", "Request body is invalid")
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > maximum:
            raise _too_large()


def _too_large() -> RequestBodyError:
    return RequestBodyError(
        HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
        "request_too_large",
        "Request body exceeds the configured limit",
    )


def _optional_ip(value: object) -> str | None:
    if value in {None, ""}:
        return None
    try:
        return str(ipaddress.ip_address(str(value)))
    except ValueError:
        return None


def _required_ip(value: object) -> str:
    normalized = _optional_ip(value)
    if normalized is None:
        raise ValueError("trusted proxy must be an IP address")
    return normalized
