"""WSGI response helpers with the API's stable security envelope."""

from __future__ import annotations

import json
import re
import uuid
from http import HTTPStatus
from typing import Mapping

_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def error_response(
    status: int,
    code: str,
    message: str,
    supplied_request_id: str | None,
) -> tuple[int, dict[str, str], bytes]:
    request_id = (
        supplied_request_id
        if supplied_request_id and _REQUEST_ID.fullmatch(supplied_request_id)
        else str(uuid.uuid4())
    )
    payload = json.dumps(
        {"code": code, "error": message, "request_id": request_id},
        separators=(",", ":"),
    ).encode("utf-8")
    return (
        int(status),
        {
            "Cache-Control": "no-store",
            "Content-Type": "application/json; charset=utf-8",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-Request-ID": request_id,
        },
        payload,
    )


def with_content_length(
    headers: Mapping[str, str],
    length: int,
) -> dict[str, str]:
    result = {
        name: value
        for name, value in headers.items()
        if name.lower() != "content-length"
    }
    result["Content-Length"] = str(length)
    return result


def status_line(status: int) -> str:
    try:
        phrase = HTTPStatus(int(status)).phrase
    except ValueError:
        phrase = "Unknown Status"
    return f"{int(status)} {phrase}"
