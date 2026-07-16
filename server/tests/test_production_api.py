from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from comicollect_backend.production_api import MAX_V1_CHANGES, ProductionApi
from comicollect_backend.rate_limit import RateLimiter
from comicollect_backend.tenant_store import TenantStore

from tests.support import (
    PASSWORD,
    MutableClock,
    bearer,
    decode_http_response,
    make_auth_service,
    token_from,
    v2_mutation_request,
)


class ProductionApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.clock = MutableClock()
        self.auth = make_auth_service(
            root / "accounts.sqlite3",
            clock=self.clock,
        )
        self.api = ProductionApi(self.auth, TenantStore(root / "tenants"))

    def request(
        self,
        method: str,
        path: str,
        payload: dict | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], dict]:
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        response = self.api.handle(method, path, headers or {}, body)
        return decode_http_response(response)

    def register(self, email: str = "reader@example.com") -> dict:
        status, _, payload = self.request(
            "POST",
            "/api/v1/auth/register",
            {
                "email": email,
                "password": PASSWORD,
                "display_name": "Reader",
                "installation_id": "installation-a",
            },
            {"content-type": "application/json"},
        )
        self.assertEqual(status, 201)
        return payload

    def test_register_login_and_authenticated_profile_contract(self) -> None:
        registered = self.register()
        status, headers, profile = self.request(
            "GET",
            "/api/v1/account/me",
            headers=bearer(token_from(registered, "access_token")),
        )
        self.assertEqual(status, 200)
        self.assertEqual(profile["account"]["email"], "reader@example.com")
        self.assertEqual(headers.get("cache-control"), "no-store")
        self.assertEqual(headers.get("x-content-type-options"), "nosniff")

        status, _, logged_in = self.request(
            "POST",
            "/api/v1/auth/login",
            {
                "email": "READER@example.com",
                "password": PASSWORD,
                "installation_id": "installation-b",
            },
            {"content-type": "application/json"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(logged_in["account"]["id"], registered["account"]["id"])

    def test_health_routes_expose_only_readiness_and_security_headers(self) -> None:
        for path in ("/health/live", "/health/ready"):
            with self.subTest(path=path):
                status, headers, payload = self.request(
                    "GET",
                    path,
                    headers={"x-request-id": "health-probe-1"},
                )
                self.assertEqual(status, 200)
                self.assertEqual(payload, {"ok": True})
                self.assertEqual(headers.get("x-request-id"), "health-probe-1")
                self.assertEqual(headers.get("cache-control"), "no-store")
                self.assertEqual(headers.get("x-content-type-options"), "nosniff")
                self.assertNotIn("server_id", payload)
                self.assertNotIn("accounts", payload)

    def test_login_does_not_enumerate_registered_email_addresses(self) -> None:
        self.register()
        responses = []
        for email, password in (
            ("reader@example.com", "wrong password that is long enough"),
            ("missing@example.com", PASSWORD),
        ):
            status, _, payload = self.request(
                "POST",
                "/api/v1/auth/login",
                {
                    "email": email,
                    "password": password,
                    "installation_id": "installation-b",
                },
                {"content-type": "application/json"},
            )
            responses.append((status, payload.get("code"), payload.get("error")))
        self.assertEqual(responses[0], responses[1])
        self.assertEqual(responses[0][0], 401)
        self.assertEqual(responses[0][1], "invalid_credentials")

    def test_refresh_endpoint_is_idempotent_then_rejects_different_request_id(self) -> None:
        registered = self.register()
        request = {
            "refresh_token": token_from(registered, "refresh_token"),
            "installation_id": "installation-a",
            "request_id": "api-refresh-request-1",
        }
        first = self.request(
            "POST",
            "/api/v1/auth/refresh",
            request,
            {"content-type": "application/json"},
        )
        retry = self.request(
            "POST",
            "/api/v1/auth/refresh",
            request,
            {"content-type": "application/json"},
        )
        self.assertEqual(first[0], 200)
        self.assertNotEqual(
            first[2]["refresh_token"],
            registered["refresh_token"],
        )
        self.assertEqual(retry[0], 200)
        self.assertEqual(retry[2], first[2])

        replay_request = dict(request, request_id="api-refresh-request-2")
        replay = self.request(
            "POST",
            "/api/v1/auth/refresh",
            replay_request,
            {"content-type": "application/json"},
        )
        self.assertEqual(replay[0], 401)
        self.assertEqual(replay[2]["code"], "refresh_reused")

    def test_refresh_request_id_is_required_by_exact_json_contract(self) -> None:
        registered = self.register()
        status, _, payload = self.request(
            "POST",
            "/api/v1/auth/refresh",
            {
                "refresh_token": token_from(registered, "refresh_token"),
                "installation_id": "installation-a",
            },
            {"content-type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["code"], "invalid_request")

    def test_duplicate_json_object_keys_are_rejected(self) -> None:
        response = self.api.handle(
            "POST",
            "/api/v1/auth/login",
            {"content-type": "application/json"},
            (
                b'{"email":"first@example.com","email":"second@example.com",'
                b'"password":"Correct horse battery staple 42!",'
                b'"installation_id":"installation-a"}'
            ),
        )

        status, _, payload = decode_http_response(response)
        self.assertEqual(status, 400)
        self.assertEqual(payload["code"], "invalid_request")
        self.assertIn("duplicate JSON field", payload["error"])

    def test_sync_account_is_derived_only_from_bearer_token(self) -> None:
        account_a = self.register("a@example.com")
        account_b = self.register("b@example.com")
        request = v2_mutation_request("Private A title")

        status, _, response_a = self.request(
            "POST",
            "/api/v2/sync",
            request,
            bearer(token_from(account_a, "access_token")),
        )
        self.assertEqual(status, 200)
        status, _, response_b = self.request(
            "POST",
            "/api/v2/sync",
            v2_mutation_request("Private B title"),
            bearer(token_from(account_b, "access_token")),
        )
        self.assertEqual(status, 200)
        self.assertEqual(response_a["acknowledgements"][0]["revision"], 1)
        self.assertEqual(response_b["acknowledgements"][0]["revision"], 1)

    def test_legacy_sync_rejects_too_many_changes_before_tenant_store(self) -> None:
        registered = self.register()
        sync_v1 = Mock(return_value=(0, []))
        self.api.tenants.sync_v1 = sync_v1

        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 0, "changes": [{}] * (MAX_V1_CHANGES + 1)},
            bearer(token_from(registered, "access_token")),
        )

        self.assertEqual(status, 400)
        self.assertEqual(payload["code"], "invalid_request")
        sync_v1.assert_not_called()

    def test_unexpected_errors_never_log_or_return_exception_secrets(self) -> None:
        registered = self.register()
        self.api.tenants.sync = Mock(side_effect=ValueError("super-secret"))

        with self.assertLogs("comicollect.production", level="ERROR") as captured:
            status, _, payload = self.request(
                "POST",
                "/api/v2/sync",
                v2_mutation_request("Trigger safe error"),
                bearer(token_from(registered, "access_token")),
            )

        logs = "\n".join(captured.output)
        self.assertEqual(status, 500)
        self.assertEqual(payload["code"], "internal_error")
        self.assertNotIn("super-secret", logs)
        self.assertNotIn("super-secret", json.dumps(payload))
        self.assertIn("ValueError", logs)

    def test_protected_routes_reject_missing_or_invalid_bearer(self) -> None:
        for headers in ({}, bearer("not-a-token")):
            with self.subTest(headers=headers):
                status, _, payload = self.request(
                    "GET", "/api/v1/account/me", headers=headers
                )
                self.assertEqual(status, 401)
                self.assertEqual(payload["code"], "invalid_token")

    def test_expired_access_token_is_distinct_and_cannot_sync(self) -> None:
        registered = self.register()
        self.clock.advance(60_001)
        status, _, payload = self.request(
            "POST",
            "/api/v2/sync",
            v2_mutation_request("Expired token write"),
            bearer(token_from(registered, "access_token")),
        )
        self.assertEqual(status, 401)
        self.assertEqual(payload["code"], "access_expired")

    def test_rate_limited_response_includes_retry_after(self) -> None:
        self.register()
        self.auth.rate_limiter = RateLimiter(
            clock=self.clock,
            limit=1,
            window_ms=60_000,
        )
        login = {
            "email": "reader@example.com",
            "password": "wrong password that is long enough",
            "installation_id": "installation-b",
        }
        first = self.request(
            "POST",
            "/api/v1/auth/login",
            login,
            {"content-type": "application/json"},
        )
        limited = self.request(
            "POST",
            "/api/v1/auth/login",
            login,
            {"content-type": "application/json"},
        )
        self.assertEqual(first[0], 401)
        self.assertEqual(limited[0], 429)
        self.assertEqual(limited[2]["code"], "rate_limited")
        self.assertGreaterEqual(int(limited[1]["retry-after"]), 1)

    def test_json_contract_rejects_unknown_fields(self) -> None:
        status, _, payload = self.request(
            "POST",
            "/api/v1/auth/register",
            {
                "email": "reader@example.com",
                "password": PASSWORD,
                "display_name": "Reader",
                "installation_id": "installation-a",
                "admin": True,
            },
            {"content-type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["code"], "invalid_request")

    def test_auth_routes_require_json_and_enforce_small_body_limit(self) -> None:
        status, _, payload = self.request(
            "POST",
            "/api/v1/auth/register",
            {"not": "json media type"},
            {"content-type": "text/plain"},
        )
        self.assertEqual(status, 415)
        self.assertEqual(payload["code"], "unsupported_media_type")

        response = self.api.handle(
            "POST",
            "/api/v1/auth/register",
            {"content-type": "application/json"},
            b"x" * (32 * 1024 + 1),
        )
        status, _, payload = decode_http_response(response)
        self.assertEqual(status, 413)
        self.assertEqual(payload["code"], "request_too_large")


if __name__ == "__main__":
    unittest.main()
