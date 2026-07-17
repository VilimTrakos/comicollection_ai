"""Framework-free JSON API and a small HTTP adapter for production routing."""

from __future__ import annotations

import ipaddress
import json
import logging
import re
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Mapping

from .api_errors import PublicApiError
from .auth_models import AuthError
from .auth_service import AuthService
from .tenant_store import TenantStore

LOG = logging.getLogger("comicollect.production")
MAX_AUTH_BODY = 32 * 1024
MAX_V1_SYNC_BODY = 1024 * 1024
MAX_SYNC_BODY = 8 * 1024 * 1024
_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class RequestValidationError(PublicApiError):
    """A deliberately public, non-sensitive request validation failure."""

    def __init__(self, message: str):
        super().__init__(HTTPStatus.BAD_REQUEST, "invalid_request", message)


class ProductionApi:
    def __init__(
        self,
        auth: AuthService,
        tenants: TenantStore,
    ):
        self.auth = auth
        self.tenants = tenants

    def handle(
        self,
        method: str,
        path: str,
        headers: Mapping[str, str] | None = None,
        body: bytes = b"",
        *,
        client_key: str = "local",
    ) -> tuple[int, dict[str, str], bytes]:
        normalized_headers = {
            str(key).lower(): str(value) for key, value in (headers or {}).items()
        }
        request_id = _request_id(normalized_headers.get("x-request-id"))
        response_headers = _security_headers(request_id)
        try:
            payload = self._route(
                method.upper(),
                path.split("?", 1)[0],
                normalized_headers,
                body,
                client_key,
            )
            status, value = payload
            return _response(status, value, response_headers)
        except PublicApiError as exc:
            return _error(
                exc.status,
                exc.code,
                str(exc),
                request_id,
                {**response_headers, **exc.headers},
            )
        except Exception as exc:
            LOG.error(
                "request failed; request_id=%s exception=%s",
                request_id,
                type(exc).__name__,
            )
            return _error(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                "internal_error",
                "Internal server error",
                request_id,
                response_headers,
            )

    def _route(
        self,
        method: str,
        path: str,
        headers: dict[str, str],
        body: bytes,
        client_key: str,
    ) -> tuple[int, dict | None]:
        if method == "GET" and path in {"/health", "/health/live"}:
            _require_empty(body)
            return HTTPStatus.OK, {"ok": True}
        if method == "GET" and path == "/health/ready":
            _require_empty(body)
            try:
                ready = self.auth.repository.ping() and self.tenants.ready()
            except Exception:
                LOG.warning("readiness check failed", exc_info=True)
                ready = False
            return (
                HTTPStatus.OK if ready else HTTPStatus.SERVICE_UNAVAILABLE,
                {"ok": ready},
            )

        if method == "POST" and path == "/api/v1/auth/register":
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(
                value,
                {"email", "password", "display_name", "installation_id"},
            )
            return HTTPStatus.CREATED, self.auth.register(
                email=value["email"],
                password=value["password"],
                display_name=value["display_name"],
                installation_id=value["installation_id"],
                rate_key=client_key,
            )
        if method == "POST" and path == "/api/v1/auth/login":
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, {"email", "password", "installation_id"})
            return HTTPStatus.OK, self.auth.login(
                email=value["email"],
                password=value["password"],
                installation_id=value["installation_id"],
                rate_key=client_key,
            )
        if method == "POST" and path == "/api/v1/auth/refresh":
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, {"refresh_token", "installation_id", "request_id"})
            return HTTPStatus.OK, self.auth.refresh(
                refresh_token=value["refresh_token"],
                installation_id=value["installation_id"],
                request_id=value["request_id"],
                rate_key=client_key,
            )
        if method == "POST" and path == "/api/v1/auth/password-reset/request":
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, {"email"})
            self.auth.request_password_reset(value["email"], rate_key=client_key)
            return HTTPStatus.ACCEPTED, {"accepted": True}
        if method == "POST" and path == "/api/v1/auth/password-reset/confirm":
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, {"token", "new_password", "request_id"})
            self.auth.confirm_password_reset(
                token=value["token"],
                new_password=value["new_password"],
                request_id=value["request_id"],
                rate_key=client_key,
            )
            return HTTPStatus.NO_CONTENT, None

        token = _bearer(headers)
        if method == "POST" and path == "/api/v1/auth/logout":
            value = _json_object(body, headers, MAX_AUTH_BODY, empty_allowed=True)
            _keys(value, set())
            self.auth.logout(token)
            return HTTPStatus.NO_CONTENT, None
        context = self.auth.authenticate_access(token)
        if (
            method == "POST"
            and path == "/api/v1/account/email-verification/request"
        ):
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, set())
            self.auth.request_email_verification(context, rate_key=client_key)
            return HTTPStatus.ACCEPTED, {"accepted": True}
        if (
            method == "POST"
            and path == "/api/v1/account/email-verification/confirm"
        ):
            value = _json_object(body, headers, MAX_AUTH_BODY)
            _keys(value, {"token", "request_id"})
            return HTTPStatus.OK, self.auth.confirm_email_verification(
                context,
                token=value["token"],
                request_id=value["request_id"],
                rate_key=client_key,
            )
        if method == "GET" and path == "/api/v1/account/me":
            _require_empty(body)
            return HTTPStatus.OK, {"account": context.account.public_json()}
        if method == "POST" and path == "/api/v2/sync":
            if context.account.email_verified_at is None:
                raise AuthError(
                    HTTPStatus.FORBIDDEN,
                    "email_not_verified",
                    "Email verification is required before synchronization",
                )
            value = _json_object(body, headers, MAX_SYNC_BODY)
            return HTTPStatus.OK, self.tenants.sync(context.account_id, value)
        if method == "POST" and path == "/api/v1/sync":
            raise PublicApiError(
                HTTPStatus.GONE,
                "sync_v1_retired",
                "Sync v1 is not available on the production account API; "
                "update the app",
            )
        raise AuthError(HTTPStatus.NOT_FOUND, "not_found", "Route not found")


class _ProductionHandler(BaseHTTPRequestHandler):
    server_version = "Comicollect"
    sys_version = ""

    def log_message(self, fmt: str, *args) -> None:
        # The explicit request log below omits query strings and credentials.
        return

    def do_GET(self) -> None:
        self._handle()

    def do_POST(self) -> None:
        self._handle()

    def do_DELETE(self) -> None:
        self._handle()

    def do_PATCH(self) -> None:
        self._handle()

    def do_PUT(self) -> None:
        self._handle()

    def _handle(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        clean_path = self.path.split("?", 1)[0]
        maximum = {
            "/api/v1/sync": MAX_V1_SYNC_BODY,
            "/api/v2/sync": MAX_SYNC_BODY,
        }.get(clean_path, MAX_AUTH_BODY)
        if length < 0 or length > maximum:
            request_id = str(uuid.uuid4())
            result = _error(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                "request_too_large",
                "Request body exceeds the configured limit",
                request_id,
                _security_headers(request_id),
            )
        else:
            body = self.rfile.read(length) if length else b""
            result = self.server.api.handle(
                self.command,
                self.path,
                dict(self.headers.items()),
                body,
                client_key=self.client_address[0],
            )
        status, headers, payload = result
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)
        LOG.info(
            "client=%s method=%s path=%s status=%s request_id=%s",
            self.client_address[0],
            self.command,
            clean_path,
            status,
            headers.get("X-Request-ID", ""),
        )


class ProductionHttpServer(ThreadingHTTPServer):
    """Development-only loopback adapter; production uses bounded Gunicorn."""

    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, api: ProductionApi):
        if not _is_loopback_host(address[0]):
            raise ValueError(
                "the development HTTP adapter may bind only to loopback; "
                "use the supported Gunicorn/nginx production profile"
            )
        super().__init__(address, _ProductionHandler)
        self.api = api


def _json_object(
    body: bytes,
    headers: dict[str, str],
    maximum: int,
    *,
    empty_allowed: bool = False,
) -> dict:
    if len(body) > maximum:
        raise AuthError(413, "request_too_large", "Request body is too large")
    if not body and empty_allowed:
        return {}
    content_type = headers.get("content-type", "").split(";", 1)[0].lower()
    if content_type != "application/json":
        raise AuthError(
            415,
            "unsupported_media_type",
            "Content-Type must be application/json",
        )
    if not body:
        raise RequestValidationError("JSON body is required")
    try:
        value = json.loads(
            body.decode("utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=lambda item: (_ for _ in ()).throw(
                RequestValidationError(f"invalid JSON constant {item}")
            ),
        )
    except (ValueError, UnicodeDecodeError) as exc:
        raise RequestValidationError("JSON body is invalid") from exc
    if not isinstance(value, dict):
        raise RequestValidationError("JSON body must be an object")
    return value


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise RequestValidationError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def _keys(value: dict, exact: set[str]) -> None:
    actual = set(value)
    if actual != exact:
        missing = sorted(exact - actual)
        unknown = sorted(actual - exact)
        detail = []
        if missing:
            detail.append("missing: " + ", ".join(missing))
        if unknown:
            detail.append("unknown: " + ", ".join(unknown))
        raise RequestValidationError(
            "invalid fields (" + "; ".join(detail) + ")"
        )


def _bearer(headers: dict[str, str]) -> str:
    value = headers.get("authorization", "")
    if not value.startswith("Bearer ") or value.count(" ") != 1:
        raise AuthError(401, "invalid_token", "Bearer token is required")
    return value[7:]


def _request_id(value: str | None) -> str:
    return value if value and _REQUEST_ID.fullmatch(value) else str(uuid.uuid4())


def _security_headers(request_id: str) -> dict[str, str]:
    return {
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
        "X-Request-ID": request_id,
    }


def _response(
    status: int, value: dict | None, headers: dict[str, str]
) -> tuple[int, dict[str, str], bytes]:
    if value is None:
        return int(status), headers, b""
    payload = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode()
    return (
        int(status),
        {**headers, "Content-Type": "application/json; charset=utf-8"},
        payload,
    )


def _error(
    status: int,
    code: str,
    message: str,
    request_id: str,
    headers: dict[str, str],
) -> tuple[int, dict[str, str], bytes]:
    return _response(
        status,
        {"code": code, "error": message, "request_id": request_id},
        headers,
    )


def _require_empty(body: bytes) -> None:
    if body:
        raise RequestValidationError("request body must be empty")


def _is_loopback_host(value: object) -> bool:
    host = str(value).strip().lower()
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False
