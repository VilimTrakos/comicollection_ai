from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path

from comicollect_backend.production_api import ProductionApi
from comicollect_backend.tenant_store import TenantStore

from tests.support import (
    PASSWORD,
    MutableClock,
    RecordingEmailSender,
    bearer,
    decode_http_response,
    empty_v2_request,
    make_auth_service,
    token_from,
)


_ACTION_TOKEN = re.compile(r"\b(?:cce|ccp)_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")


class AccountActionApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.clock = MutableClock()
        self.sender = RecordingEmailSender()
        self.auth = make_auth_service(
            root / "accounts.sqlite3",
            clock=self.clock,
            email_sender=self.sender,
        )
        self.api = ProductionApi(self.auth, TenantStore(root / "tenants"))

    def request(
        self,
        path: str,
        payload: dict,
        *,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], dict]:
        request_headers = {"content-type": "application/json", **(headers or {})}
        response = self.api.handle(
            "POST",
            path,
            request_headers,
            json.dumps(payload).encode("utf-8"),
            client_key="203.0.113.8",
        )
        return decode_http_response(response)

    def register(self, email: str = "reader@example.com") -> dict:
        status, _, payload = self.request(
            "/api/v1/auth/register",
            {
                "email": email,
                "password": PASSWORD,
                "display_name": "Reader",
                "installation_id": "installation-a",
            },
        )
        self.assertEqual(status, 201)
        self.assertFalse(payload["account"]["email_verified"])
        return payload

    def test_verification_routes_gate_sync_until_confirmation(self) -> None:
        registered = self.register()
        authorization = bearer(token_from(registered, "access_token"))

        status, _, blocked = self.request(
            "/api/v2/sync",
            empty_v2_request("sync-before-verification"),
            headers=authorization,
        )
        self.assertEqual(status, 403)
        self.assertEqual(blocked["code"], "email_not_verified")

        status, _, accepted = self.request(
            "/api/v1/account/email-verification/request",
            {},
            headers=authorization,
        )
        self.assertEqual(status, 202)
        self.assertEqual(accepted, {"accepted": True})
        token = _message_token(self.sender.messages[-1].text_body, "cce_")

        status, _, confirmed = self.request(
            "/api/v1/account/email-verification/confirm",
            {"token": token, "request_id": "verification-api-request"},
            headers=authorization,
        )
        self.assertEqual(status, 200)
        self.assertTrue(confirmed["account"]["email_verified"])

        status, _, synchronized = self.request(
            "/api/v2/sync",
            empty_v2_request("sync-after-verification"),
            headers=authorization,
        )
        self.assertEqual(status, 200)
        self.assertEqual(synchronized["protocol"], 2)

    def test_password_reset_request_does_not_enumerate_accounts(self) -> None:
        self.register()
        existing = self.request(
            "/api/v1/auth/password-reset/request",
            {"email": "reader@example.com"},
        )
        message_count = len(self.sender.messages)
        missing = self.request(
            "/api/v1/auth/password-reset/request",
            {"email": "missing@example.com"},
        )

        self.assertEqual((existing[0], existing[2]), (missing[0], missing[2]))
        self.assertEqual((existing[0], existing[2]), (202, {"accepted": True}))
        self.assertEqual(len(self.sender.messages), message_count)

    def test_password_reset_confirmation_returns_no_content_and_is_retryable(
        self,
    ) -> None:
        self.register()
        self.request(
            "/api/v1/auth/password-reset/request",
            {"email": "reader@example.com"},
        )
        token = _message_token(self.sender.messages[-1].text_body, "ccp_")
        payload = {
            "token": token,
            "new_password": "A replacement secure passphrase 84!",
            "request_id": "password-reset-api-request",
        }

        first = self.request("/api/v1/auth/password-reset/confirm", payload)
        retry = self.request("/api/v1/auth/password-reset/confirm", payload)

        self.assertEqual(first[0], 204)
        self.assertEqual(first[2], {})
        self.assertEqual((retry[0], retry[2]), (first[0], first[2]))

    def test_action_routes_enforce_bearer_and_exact_json_contract(self) -> None:
        registered = self.register()
        authorization = bearer(token_from(registered, "access_token"))
        missing_bearer = self.request(
            "/api/v1/account/email-verification/request",
            {},
        )
        unknown_field = self.request(
            "/api/v1/account/email-verification/request",
            {"unexpected": True},
            headers=authorization,
        )
        reset_unknown_field = self.request(
            "/api/v1/auth/password-reset/request",
            {"email": "reader@example.com", "unexpected": True},
        )

        self.assertEqual(missing_bearer[0], 401)
        self.assertEqual(missing_bearer[2]["code"], "invalid_token")
        self.assertEqual(unknown_field[0], 400)
        self.assertEqual(reset_unknown_field[0], 400)


def _message_token(body: str, prefix: str) -> str:
    match = _ACTION_TOKEN.search(body)
    if match is None or not match.group(0).startswith(prefix):
        raise AssertionError(f"missing {prefix} action token")
    return match.group(0)


if __name__ == "__main__":
    unittest.main()
