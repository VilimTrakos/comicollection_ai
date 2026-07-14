import http.client
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from comicollect_server import FIELDS, MAX_BODY, Server, Store, validate_comic


def comic(updated=100, title="Morgana", **overrides):
    value = {
        "id": "one",
        "series": "Dylan Dog",
        "edition": "Extra",
        "number": 25,
        "title": title,
        "updated_at": updated,
        "owned": 1,
        "is_read": 0,
        "condition_grade": "VF",
        "is_duplicate": 0,
        "deleted": 0,
        "cover_asset": "assets/catalog/covers/ddlu/0061.webp",
    }
    value.update(overrides)
    return value


class ValidationTest(unittest.TestCase):
    def test_defaults_and_supported_values_are_normalized(self):
        cleaned = validate_comic(
            comic(
                year="2002",
                owned="yes",
                is_read=1,
                purchase_price="3.5",
                estimated_value=7,
                is_duplicate=True,
                rating=99,
                page_count="98",
                deleted=True,
            )
        )
        self.assertEqual(set(cleaned), set(FIELDS))
        self.assertEqual(cleaned["year"], 2002)
        self.assertEqual(cleaned["owned"], 1)
        self.assertEqual(cleaned["purchase_price"], 3.5)
        self.assertEqual(cleaned["rating"], 5)
        self.assertEqual(cleaned["page_count"], 98)
        self.assertEqual(cleaned["deleted"], 1)
        self.assertEqual(cleaned["publisher"], "")
        self.assertEqual(cleaned["writer"], "")

    def test_default_condition_and_rating_lower_bound(self):
        value = comic(rating=-4)
        value.pop("condition_grade")
        cleaned = validate_comic(value)
        self.assertEqual(cleaned["condition_grade"], "F")
        self.assertEqual(cleaned["rating"], 0)

    def test_text_fields_are_truncated_to_protocol_limits(self):
        cleaned = validate_comic(
            comic(
                id="x" * 100,
                series="s" * 250,
                edition="e" * 250,
                title="t" * 600,
                publisher="p" * 250,
                loaned_to="l" * 350,
                notes="n" * 10050,
                cover_asset="c" * 550,
                writer="w" * 350,
                artist="a" * 350,
            )
        )
        expected = {
            "id": 64,
            "series": 200,
            "edition": 200,
            "title": 500,
            "publisher": 200,
            "loaned_to": 300,
            "notes": 10000,
            "cover_asset": 500,
            "writer": 300,
            "artist": 300,
        }
        for field, length in expected.items():
            self.assertEqual(len(cleaned[field]), length)

    def test_rejects_non_object_missing_fields_and_invalid_identity(self):
        with self.assertRaisesRegex(ValueError, "object"):
            validate_comic([])
        with self.assertRaisesRegex(ValueError, "missing required"):
            validate_comic({"id": "one"})
        for bad in (
            comic(id=""),
            comic(series=""),
            comic(number=-1),
        ):
            with self.assertRaisesRegex(ValueError, "invalid id"):
                validate_comic(bad)

    def test_rejects_bad_grade_and_non_numeric_fields(self):
        for grade in ("BAD", "mint", "VF+"):
            with self.assertRaisesRegex(ValueError, "condition_grade"):
                validate_comic(comic(condition_grade=grade))
        with self.assertRaises((TypeError, ValueError)):
            validate_comic(comic(number="not-a-number"))
        with self.assertRaises((TypeError, ValueError)):
            validate_comic(comic(updated_at=None))

    def test_accepts_every_documented_condition_grade(self):
        for grade in ("", "M", "VF", "F", "G", "P"):
            self.assertEqual(
                validate_comic(comic(condition_grade=grade))["condition_grade"],
                grade,
            )


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / "db.sqlite3")

    def tearDown(self):
        self.tmp.cleanup()

    def test_schema_has_indexes_and_all_current_columns(self):
        with self.store.connect() as db:
            columns = {row[1] for row in db.execute("PRAGMA table_info(comics)")}
            indexes = {row[1] for row in db.execute("PRAGMA index_list(comics)")}
        self.assertEqual(columns, set(FIELDS))
        self.assertIn("idx_updated", indexes)
        self.assertIn("idx_series", indexes)

    def test_sync_and_newest_write_wins(self):
        _, rows = self.store.sync(0, [comic()])
        self.assertEqual(rows[0]["title"], "Morgana")
        self.assertEqual(
            rows[0]["cover_asset"],
            "assets/catalog/covers/ddlu/0061.webp",
        )
        self.store.sync(0, [comic(99, "Older")])
        self.store.sync(0, [comic(100, "Equal timestamp")])
        _, rows = self.store.sync(0, [])
        self.assertEqual(rows[0]["title"], "Morgana")
        self.store.sync(0, [comic(101, "Newer")])
        _, rows = self.store.sync(100, [])
        self.assertEqual([row["title"] for row in rows], ["Newer"])

    def test_sync_orders_changes_and_honors_since_cursor(self):
        self.store.sync(
            0,
            [
                comic(300, "Third", id="three", number=3),
                comic(100, "First", id="one", number=1),
                comic(200, "Second", id="two", number=2),
            ],
        )
        _, rows = self.store.sync(100, [])
        self.assertEqual([row["id"] for row in rows], ["two", "three"])
        _, rows = self.store.sync(300, [])
        self.assertEqual(rows, [])

    def test_sync_keeps_all_issue_metadata(self):
        value = comic(
            rating=4,
            page_count=98,
            writer="Tiziano Sclavi",
            artist="Angelo Stano",
            year=2002,
            publisher="Ludens",
            purchase_price=4.5,
            estimated_value=7.0,
            loaned_to="Ana",
            notes="Potpisano",
        )
        _, rows = self.store.sync(0, [value])
        row = rows[0]
        for key in (
            "rating",
            "page_count",
            "writer",
            "artist",
            "year",
            "publisher",
            "purchase_price",
            "estimated_value",
            "loaned_to",
            "notes",
        ):
            self.assertEqual(row[key], validate_comic(value)[key])

    def test_stats_distinguish_tombstones_from_active_records(self):
        self.store.sync(
            0,
            [comic(id="active"), comic(id="gone", deleted=True, updated_at=101)],
        )
        self.assertEqual(self.store.stats(), {"records": 2, "active": 1})

    def test_backup_is_readable_and_retains_only_fourteen_files(self):
        self.store.sync(0, [comic()])
        destination = Path(self.tmp.name) / "backups"
        destination.mkdir()
        for index in range(16):
            (destination / f"comicollect-20000101-0000{index:02}.sqlite3").touch()
        target = self.store.backup(destination)
        self.assertTrue(target.exists())
        self.assertLessEqual(
            len(list(destination.glob("comicollect-*.sqlite3"))),
            14,
        )
        with sqlite3.connect(target) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM comics").fetchone()[0], 1)


class ApiTest(unittest.TestCase):
    token = "t" * 32

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / "api.sqlite3")
        self.server = Server(("127.0.0.1", 0), self.store, self.token)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.tmp.cleanup()

    def request(self, method, path, payload=None, *, raw=None, headers=None):
        body = raw
        request_headers = dict(headers or {})
        if payload is not None:
            body = json.dumps(payload).encode()
            request_headers.setdefault("Content-Type", "application/json")
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        data = json.loads(response.read())
        result = (response.status, dict(response.getheaders()), data)
        connection.close()
        return result

    def auth(self):
        return {"Authorization": f"Bearer {self.token}"}

    def test_health_and_unknown_routes(self):
        status, headers, payload = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"ok": True, "version": 1, "records": 0, "active": 0})
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertEqual(self.request("GET", "/missing")[0], 404)
        self.assertEqual(self.request("POST", "/missing")[0], 404)

    def test_sync_requires_an_exact_bearer_token(self):
        payload = {"since": 0, "changes": []}
        self.assertEqual(self.request("POST", "/api/v1/sync", payload)[0], 401)
        self.assertEqual(
            self.request(
                "POST",
                "/api/v1/sync",
                payload,
                headers={"Authorization": "Bearer wrong"},
            )[0],
            401,
        )
        self.assertEqual(
            self.request(
                "POST",
                "/api/v1/sync",
                payload,
                headers=self.auth(),
            )[0],
            200,
        )

    def test_sync_round_trip_returns_server_cursor_and_remote_changes(self):
        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 0, "changes": [comic()]},
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        self.assertIsInstance(payload["server_time"], int)
        self.assertEqual(payload["changes"][0]["title"], "Morgana")
        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 100, "changes": []},
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["changes"], [])

    def test_bad_json_body_size_payload_and_comic_return_400(self):
        cases = [
            {"raw": b"", "headers": self.auth()},
            {"raw": b"{", "headers": self.auth()},
            {
                "payload": {"since": 0, "changes": "wrong"},
                "headers": self.auth(),
            },
            {
                "payload": {"since": 0, "changes": [None] * 10001},
                "headers": self.auth(),
            },
            {
                "payload": {"since": 0, "changes": [{"id": "missing"}]},
                "headers": self.auth(),
            },
        ]
        for case in cases:
            with self.subTest(case=list(case)):
                status, _, payload = self.request("POST", "/api/v1/sync", **case)
                self.assertEqual(status, 400)
                self.assertIn("error", payload)

        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            raw=b"",
            headers={**self.auth(), "Content-Length": str(MAX_BODY + 1)},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid body size")

    def test_negative_since_is_clamped_to_zero(self):
        self.store.sync(0, [comic()])
        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": -99, "changes": []},
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["changes"]), 1)

    def test_unexpected_store_failure_is_hidden_from_clients(self):
        class BrokenStore:
            def sync(self, since, changes):
                raise RuntimeError("database password must stay private")

        original = self.server.store
        self.server.store = BrokenStore()
        try:
            status, _, payload = self.request(
                "POST",
                "/api/v1/sync",
                {"since": 0, "changes": []},
                headers=self.auth(),
            )
        finally:
            self.server.store = original
        self.assertEqual(status, 500)
        self.assertEqual(payload, {"error": "internal error"})


if __name__ == "__main__":
    unittest.main()
