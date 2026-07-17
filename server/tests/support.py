from __future__ import annotations

import json
from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Iterator, Mapping

from comicollect_backend.auth_repository import AuthRepository
from comicollect_backend.auth_service import AuthService
from comicollect_backend.email_delivery import DeliveryReceipt, EmailSender, OutboundEmail
from comicollect_backend.passwords import PasswordHasher, ScryptParams


PASSWORD = "Correct horse battery staple 42!"
PEPPER = b"p" * 32


class RecordingEmailSender:
    def __init__(self):
        self.messages: list[OutboundEmail] = []

    def send(self, message: OutboundEmail) -> DeliveryReceipt:
        self.messages.append(message)
        return DeliveryReceipt(provider_message_id=f"recording-{len(self.messages)}")


class MutableClock:
    """Deterministic millisecond clock accepted by the backend services."""

    def __init__(self, value: int = 1_700_000_000_000):
        self.value = value

    def now_ms(self) -> int:
        return self.value

    def __call__(self) -> int:
        return self.value

    def advance(self, milliseconds: int) -> None:
        self.value += milliseconds


def mapping(value: Any) -> dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    if is_dataclass(value):
        return asdict(value)
    if hasattr(value, "to_dict"):
        result = value.to_dict()
        if isinstance(result, Mapping):
            return dict(result)
    raise AssertionError(f"expected a mapping-like result, got {type(value)!r}")


def account_from(result: Any) -> dict[str, Any]:
    data = mapping(result)
    account = data.get("account")
    return mapping(account) if account is not None else data


def token_from(result: Any, name: str) -> str:
    token = mapping(result).get(name)
    if not isinstance(token, str) or not token:
        raise AssertionError(f"missing non-empty {name}")
    return token


@contextmanager
def error_code(test, expected: str) -> Iterator[None]:
    try:
        yield
    except Exception as error:  # The stable wire code is the public contract.
        test.assertEqual(getattr(error, "code", None), expected)
    else:
        test.fail(f"expected backend error {expected!r}")


def make_hasher(
    *,
    pepper: bytes = PEPPER,
    n: int = 16,
) -> PasswordHasher:
    return PasswordHasher(
        pepper=pepper,
        params=ScryptParams(
            n=n,
            r=1,
            p=1,
            dklen=32,
            maxmem=128 * 1024 * 1024,
        ),
    )


def make_auth_service(
    database: Path,
    *,
    clock: MutableClock | None = None,
    access_ttl_ms: int = 60_000,
    refresh_ttl_ms: int = 600_000,
    registration_enabled: bool = True,
    email_sender: EmailSender | None = None,
    email_verification_ttl_ms: int = 24 * 60 * 60 * 1000,
    password_reset_ttl_ms: int = 60 * 60 * 1000,
) -> AuthService:
    return AuthService(
        repository=AuthRepository(database),
        hasher=make_hasher(),
        token_key=PEPPER,
        clock=clock or MutableClock(),
        access_ttl_ms=access_ttl_ms,
        refresh_ttl_ms=refresh_ttl_ms,
        session_ttl_ms=3_600_000,
        registration_enabled=registration_enabled,
        email_sender=email_sender,
        email_verification_ttl_ms=email_verification_ttl_ms,
        password_reset_ttl_ms=password_reset_ttl_ms,
    )


def registration(
    service: AuthService,
    email: str = "reader@example.com",
    *,
    installation_id: str = "installation-a",
) -> Any:
    return service.register(
        email=email,
        password=PASSWORD,
        display_name="Reader",
        installation_id=installation_id,
    )


def v2_mutation_request(
    title: str,
    *,
    request_id: str = "request-shared",
    mutation_id: str = "mutation-shared",
    cursor: int = 0,
) -> dict[str, Any]:
    return {
        "protocol": 2,
        "request_id": request_id,
        "device_id": "device-shared",
        "cursor": cursor,
        "limit": 100,
        "mutations": [
            {
                "mutation_id": mutation_id,
                "created_at": 1_700_000_000_000,
                "changes": [
                    {
                        "entity_type": "custom_issue",
                        "entity_id": "same-issue-id",
                        "operation": "upsert",
                        "data": {
                            "series": "Dylan Dog",
                            "edition": "Extra",
                            "number": 1,
                            "title": title,
                            "publisher": "Ludens",
                            "year": 2002,
                            "page_count": 98,
                            "writer": "Tiziano Sclavi",
                            "artist": "Angelo Stano",
                        },
                    }
                ],
            }
        ],
    }


def empty_v2_request(
    request_id: str,
    *,
    cursor: int = 0,
    server_id: str | None = None,
) -> dict[str, Any]:
    request: dict[str, Any] = {
        "protocol": 2,
        "request_id": request_id,
        "device_id": "device-reader",
        "cursor": cursor,
        "limit": 100,
        "mutations": [],
    }
    if server_id is not None:
        request["server_id"] = server_id
    return request


def decode_http_response(response: Any) -> tuple[int, dict[str, str], dict[str, Any]]:
    if isinstance(response, tuple) and len(response) == 3:
        status, headers, body = response
    else:
        status = response.status
        headers = response.headers
        body = response.body
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    payload = json.loads(body) if isinstance(body, str) and body else {}
    return int(status), {str(k).lower(): str(v) for k, v in dict(headers).items()}, payload


def bearer(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}", "content-type": "application/json"}
