from __future__ import annotations

import io
import json
import os
import runpy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from comicollect_backend.production_api import MAX_AUTH_BODY, MAX_V1_SYNC_BODY
from comicollect_backend.wsgi import WsgiApplication
from comicollect_wsgi import check_application, create_application


class _RecordingApi:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def handle(
        self,
        method: str,
        path: str,
        headers: dict[str, str],
        body: bytes,
        *,
        client_key: str,
    ) -> tuple[int, dict[str, str], bytes]:
        self.calls.append(
            {
                "method": method,
                "path": path,
                "headers": headers,
                "body": body,
                "client_key": client_key,
            }
        )
        return 202, {"Content-Type": "application/json"}, b'{"ok":true}'


class _NeverRead:
    def read(self, size: int = -1) -> bytes:
        raise AssertionError("oversized declared bodies must not be read")


class _PartialInput:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload

    def read(self, size: int = -1) -> bytes:
        if not self.payload:
            return b""
        count = min(2, size, len(self.payload))
        chunk, self.payload = self.payload[:count], self.payload[count:]
        return chunk


class WsgiApplicationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.api = _RecordingApi()
        self.application = WsgiApplication(
            self.api,
            trusted_proxy_addresses=("127.0.0.1", "::1"),
        )

    def request(
        self,
        *,
        method: str = "GET",
        path: str = "/health/live",
        query: str = "",
        body: bytes = b"",
        remote: str = "203.0.113.9",
        headers: dict[str, str] | None = None,
        content_length: str | None = None,
        stream: object | None = None,
        terminated: bool = False,
    ) -> tuple[str, dict[str, str], bytes]:
        environ: dict[str, object] = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": query,
            "REMOTE_ADDR": remote,
            "wsgi.input": stream or io.BytesIO(body),
        }
        if content_length is not None:
            environ["CONTENT_LENGTH"] = content_length
        elif body:
            environ["CONTENT_LENGTH"] = str(len(body))
        if terminated:
            environ["wsgi.input_terminated"] = True
        for name, value in (headers or {}).items():
            key = "HTTP_" + name.upper().replace("-", "_")
            if name.lower() == "content-type":
                key = "CONTENT_TYPE"
            environ[key] = value

        captured: dict[str, object] = {}

        def start_response(status, response_headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = dict(response_headers)

        payload = b"".join(self.application(environ, start_response))
        return (
            str(captured["status"]),
            dict(captured["headers"]),
            payload,
        )

    def test_translates_wsgi_request_and_sets_exact_response_length(self) -> None:
        status, headers, payload = self.request(
            method="POST",
            path="/api/v1/auth/login",
            query="source=mobile",
            body=b'{"hello":"world"}',
            headers={"Content-Type": "application/json", "X-Test": "yes"},
            stream=_PartialInput(b'{"hello":"world"}'),
        )

        self.assertEqual(status, "202 Accepted")
        self.assertEqual(payload, b'{"ok":true}')
        self.assertEqual(headers["Content-Length"], str(len(payload)))
        self.assertEqual(self.api.calls[0]["method"], "POST")
        self.assertEqual(
            self.api.calls[0]["path"],
            "/api/v1/auth/login?source=mobile",
        )
        self.assertEqual(self.api.calls[0]["body"], b'{"hello":"world"}')
        self.assertEqual(
            self.api.calls[0]["headers"]["Content-Type"],
            "application/json",
        )

    def test_only_a_trusted_direct_proxy_can_supply_client_ip(self) -> None:
        self.request(
            remote="127.0.0.1",
            headers={"X-Real-IP": "198.51.100.7"},
        )
        self.assertEqual(self.api.calls[-1]["client_key"], "198.51.100.7")

        self.request(
            remote="203.0.113.8",
            headers={"X-Real-IP": "198.51.100.99"},
        )
        self.assertEqual(self.api.calls[-1]["client_key"], "203.0.113.8")

        self.request(
            remote="127.0.0.1",
            headers={"X-Real-IP": "not-an-ip"},
        )
        self.assertEqual(self.api.calls[-1]["client_key"], "127.0.0.1")

    def test_rejects_declared_oversize_without_reading_or_calling_api(self) -> None:
        status, headers, body = self.request(
            method="POST",
            path="/api/v1/auth/login",
            content_length=str(MAX_AUTH_BODY + 1),
            stream=_NeverRead(),
            headers={"X-Request-ID": "oversize-1"},
        )

        self.assertTrue(status.startswith("413 "))
        self.assertEqual(json.loads(body)["code"], "request_too_large")
        self.assertEqual(headers["X-Request-ID"], "oversize-1")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(self.api.calls, [])

    def test_legacy_sync_has_a_smaller_early_body_limit(self) -> None:
        status, _, body = self.request(
            method="POST",
            path="/api/v1/sync",
            content_length=str(MAX_V1_SYNC_BODY + 1),
            stream=_NeverRead(),
        )

        self.assertTrue(status.startswith("413 "))
        self.assertEqual(json.loads(body)["code"], "request_too_large")
        self.assertEqual(self.api.calls, [])

    def test_chunked_body_is_bounded_when_server_marks_input_terminated(self) -> None:
        status, _, body = self.request(
            method="POST",
            path="/api/v1/auth/login",
            stream=io.BytesIO(b"x" * (MAX_AUTH_BODY + 1)),
            terminated=True,
        )

        self.assertTrue(status.startswith("413 "))
        self.assertEqual(json.loads(body)["code"], "request_too_large")
        self.assertEqual(self.api.calls, [])

    def test_invalid_or_truncated_content_length_has_stable_json_error(self) -> None:
        invalid = self.request(
            method="POST",
            content_length="+12",
        )
        self.assertEqual(invalid[0], "400 Bad Request")
        self.assertEqual(
            json.loads(invalid[2])["code"],
            "invalid_content_length",
        )

        truncated = self.request(
            method="POST",
            content_length="10",
            stream=io.BytesIO(b"short"),
        )
        self.assertEqual(truncated[0], "400 Bad Request")
        self.assertEqual(json.loads(truncated[2])["code"], "invalid_body")
        self.assertEqual(self.api.calls, [])

    def test_invalid_trusted_proxy_configuration_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "trusted proxy"):
            WsgiApplication(self.api, trusted_proxy_addresses=("proxy.local",))

    def test_factory_import_is_lazy_but_configuration_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "exactly one"):
            create_application({})

    def test_production_check_enforces_database_and_disk_readiness(self) -> None:
        repository = SimpleNamespace(ping=lambda: True)
        tenants = SimpleNamespace(ready=lambda: True)
        application = SimpleNamespace(
            api=SimpleNamespace(
                auth=SimpleNamespace(repository=repository),
                tenants=tenants,
            )
        )

        check_application(application)

        application.api.auth.repository = SimpleNamespace(ping=lambda: False)
        with self.assertRaisesRegex(RuntimeError, "auth database"):
            check_application(application)

        application.api.auth.repository = repository
        application.api.tenants = SimpleNamespace(ready=lambda: False)
        with self.assertRaisesRegex(RuntimeError, "tenant storage"):
            check_application(application)

    def test_factory_builds_the_real_dependency_graph_from_valid_config(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pepper = root / "pepper"
            pepper.write_bytes(b"p" * 32)
            pepper.chmod(0o440)
            application = create_application(
                {
                    "COMICOLLECT_DATA_ROOT": str(root / "data"),
                    "COMICOLLECT_PASSWORD_PEPPER_FILE": str(pepper),
                    "COMICOLLECT_PUBLIC_REGISTRATION": "false",
                }
            )
            previous = self.application
            self.application = application
            try:
                status, _, payload = self.request(path="/health/ready")
            finally:
                self.application = previous

            self.assertEqual(status, "200 OK")
            self.assertEqual(json.loads(payload), {"ok": True})
            self.assertTrue((root / "data" / "accounts.sqlite3").exists())

    def test_factory_injects_configured_email_sender_into_account_actions(self) -> None:
        sender = object()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pepper = root / "pepper"
            pepper.write_bytes(b"p" * 32)
            pepper.chmod(0o440)
            with patch("comicollect_wsgi.build_email_sender", return_value=sender) as build:
                application = create_application(
                    {
                        "COMICOLLECT_DATA_ROOT": str(root / "data"),
                        "COMICOLLECT_PASSWORD_PEPPER_FILE": str(pepper),
                        "COMICOLLECT_PUBLIC_REGISTRATION": "false",
                    }
                )

        build.assert_called_once()
        self.assertIs(application.api.auth.account_actions.email_sender, sender)

    def test_gunicorn_profile_preserves_single_process_invariants(self) -> None:
        config_path = Path(__file__).parents[1] / "gunicorn.conf.py"
        with patch.dict(
            os.environ,
            {
                "COMICOLLECT_PORT": "9123",
                "COMICOLLECT_GUNICORN_THREADS": "4",
                "COMICOLLECT_REQUEST_TIMEOUT_SECONDS": "25",
            },
            clear=True,
        ):
            config = runpy.run_path(str(config_path))

        self.assertEqual(config["workers"], 1)
        self.assertEqual(config["worker_class"], "gthread")
        self.assertEqual(config["threads"], 4)
        self.assertEqual(config["bind"], "127.0.0.1:9123")
        self.assertEqual(config["timeout"], 25)
        self.assertIn("%(U)s", config["access_log_format"])
        self.assertNotIn("%(r)s", config["access_log_format"])
        self.assertNotIn("%(q)s", config["access_log_format"])
        self.assertEqual(
            config["wsgi_app"],
            "comicollect_wsgi:create_application()",
        )

        with patch.dict(
            os.environ,
            {"COMICOLLECT_GUNICORN_THREADS": "99"},
            clear=True,
        ):
            with self.assertRaisesRegex(RuntimeError, "between 2 and 4"):
                runpy.run_path(str(config_path))


if __name__ == "__main__":
    unittest.main()
