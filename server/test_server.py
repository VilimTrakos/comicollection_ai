import http.client
import json
import sqlite3
import tempfile
import threading
import unittest
from contextlib import closing
from copy import deepcopy
from pathlib import Path
from unittest import mock

from comicollect_server import (
    FIELDS,
    MAX_BODY,
    MAX_V2_LIMIT,
    MAX_V2_TOTAL_CHANGES,
    ApiError,
    Server,
    Store,
    V1WriteConflict,
    validate_comic,
    validate_v2_request,
)


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


def issue_data(title="Morgana", **overrides):
    value = {
        "series": "Dylan Dog",
        "edition": "Extra",
        "number": 25,
        "title": title,
        "publisher": "Ludens",
        "year": 2002,
        "page_count": 98,
        "writer": "Tiziano Sclavi",
        "artist": "Angelo Stano",
    }
    value.update(overrides)
    return value


def hint_data(issue_id="one", title="Morgana", origin="bundled", **overrides):
    value = {
        "id": issue_id,
        "series": "Dylan Dog",
        "edition": "Extra",
        "number": 25,
        "title": title,
        "publisher": "Ludens",
        "year": 2002,
        "origin": origin,
    }
    value.update(overrides)
    return value


def entry_data(issue_id="one", updated=100, **overrides):
    value = {
        "issue_id": issue_id,
        "owned": True,
        "is_wanted": False,
        "is_read": False,
        "is_duplicate": False,
        "rating": 0,
        "notes": "",
        "deleted": False,
        "updated_at": updated,
    }
    value.update(overrides)
    return value


def copy_data(issue_id="one", updated=100, **overrides):
    value = {
        "issue_id": issue_id,
        "ordinal": 0,
        "active": True,
        "condition_grade": "VF",
        "purchase_price": 3.5,
        "estimated_value": 7.0,
        "loaned_to": "",
        "deleted": False,
        "updated_at": updated,
    }
    value.update(overrides)
    return value


def change(entity_type, entity_id, data, operation="upsert"):
    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "operation": operation,
        "data": data,
    }


def mutation(mutation_id="mutation-1", changes=None, created_at=100):
    return {
        "mutation_id": mutation_id,
        "created_at": created_at,
        "changes": changes
        if changes is not None
        else [change("custom_issue", "one", issue_data())],
    }


def v2_request(
    request_id="request-1",
    *,
    cursor=0,
    limit=100,
    mutations=None,
    server_id=None,
):
    value = {
        "protocol": 2,
        "request_id": request_id,
        "device_id": "device-1",
        "cursor": cursor,
        "limit": limit,
        "mutations": mutations if mutations is not None else [mutation()],
    }
    if server_id is not None:
        value["server_id"] = server_id
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


class V2ValidationTest(unittest.TestCase):
    def test_normalizes_the_complete_authority_payload(self):
        request = v2_request(
            mutations=[
                mutation(
                    changes=[
                        change("custom_issue", "one", issue_data()),
                        change("collection_entry", "one", entry_data()),
                        change("copy", "copy-one", copy_data()),
                        change(
                            "barcode_mapping",
                            "9789530000000",
                            {
                                "issue_id": "one",
                                "deleted": False,
                                "updated_at": 100,
                            },
                        ),
                    ]
                )
            ]
        )

        normalized = validate_v2_request(request)

        self.assertEqual(normalized["protocol"], 2)
        self.assertEqual(len(normalized["mutations"][0]["changes"]), 4)
        self.assertIs(normalized["mutations"][0]["changes"][1]["data"]["owned"], True)

    def test_rejects_coercion_unknown_fields_and_bad_delete_contract(self):
        cases = []
        wrong_protocol = v2_request()
        wrong_protocol["protocol"] = "2"
        cases.append(wrong_protocol)
        boolean_cursor = v2_request()
        boolean_cursor["cursor"] = True
        cases.append(boolean_cursor)
        unknown = v2_request()
        unknown["extra"] = 1
        cases.append(unknown)
        wrong_bool = v2_request(
            mutations=[
                mutation(
                    changes=[
                        change(
                            "collection_entry",
                            "one",
                            entry_data(owned=1, issue_hint=hint_data()),
                        )
                    ]
                )
            ]
        )
        cases.append(wrong_bool)
        inconsistent_delete = v2_request(
            mutations=[
                mutation(
                    changes=[
                        change(
                            "collection_entry",
                            "one",
                            entry_data(deleted=False, issue_hint=hint_data()),
                            operation="delete",
                        )
                    ]
                )
            ]
        )
        cases.append(inconsistent_delete)
        infinite_price = v2_request(
            mutations=[
                mutation(
                    changes=[
                        change(
                            "copy",
                            "copy-one",
                            copy_data(
                                purchase_price=float("inf"),
                                issue_hint=hint_data(),
                            ),
                        )
                    ]
                )
            ]
        )
        cases.append(infinite_price)

        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    validate_v2_request(value)

    def test_enforces_request_group_and_page_limits(self):
        too_many_groups = v2_request(
            mutations=[mutation(f"m-{index}") for index in range(101)]
        )
        too_large_page = v2_request(limit=MAX_V2_LIMIT + 1)
        empty_group = v2_request(mutations=[mutation(changes=[])])

        for value in (too_many_groups, too_large_page, empty_group):
            with self.assertRaises(ValueError):
                validate_v2_request(value)


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / "db.sqlite3")

    def tearDown(self):
        self.tmp.cleanup()

    def test_schema_has_indexes_and_all_current_columns(self):
        with closing(self.store.connect()) as db, db:
            columns = {row[1] for row in db.execute("PRAGMA table_info(comics)")}
            indexes = {row[1] for row in db.execute("PRAGMA index_list(comics)")}
            synchronous = db.execute("PRAGMA synchronous").fetchone()[0]
        self.assertEqual(columns, set(FIELDS))
        self.assertIn("idx_updated", indexes)
        self.assertIn("idx_series", indexes)
        self.assertEqual(synchronous, 2)

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
        with closing(sqlite3.connect(target)) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM comics").fetchone()[0], 1)


class V2StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "v2.sqlite3"
        self.store = Store(self.path)

    def tearDown(self):
        self.tmp.cleanup()

    def test_empty_v2_poll_keeps_v1_writable_until_first_v2_mutation(self):
        self.store.sync(0, [comic()])

        response = self.store.sync_v2(
            v2_request(request_id="poll", mutations=[])
        )

        self.assertEqual(response["protocol"], 2)
        self.assertEqual(response["next_cursor"], 1)
        self.assertEqual(len(response["change_groups"]), 1)
        self.assertEqual(
            {change["entity_type"] for change in response["change_groups"][0]["changes"]},
            {"custom_issue", "collection_entry", "copy"},
        )
        self.store.sync(0, [comic(updated=101, title="Still mirrored")])
        activated = self.store.sync_v2(
            v2_request(
                request_id="activate",
                cursor=response["next_cursor"],
                mutations=[
                    mutation(
                        "first-v2-write",
                        changes=[
                            change("custom_issue", "new", issue_data(title="New"))
                        ],
                    )
                ],
            )
        )
        self.assertEqual(activated["acknowledgements"][0]["status"], "applied")
        # A lost v1 HTTP response may be retried after another client has
        # activated v2. Its exact already-committed payload is a safe no-op.
        _, retried = self.store.sync(
            0, [comic(updated=101, title="Still mirrored")]
        )
        self.assertEqual(retried[0]["title"], "Still mirrored")
        with closing(self.store.connect()) as db:
            groups_before = db.execute(
                "SELECT COUNT(*) FROM v2_change_groups"
            ).fetchone()[0]
        _, stale_retry = self.store.sync(
            0, [comic(updated=100, title="Must remain ignored")]
        )
        with closing(self.store.connect()) as db:
            groups_after = db.execute(
                "SELECT COUNT(*) FROM v2_change_groups"
            ).fetchone()[0]
        self.assertEqual(groups_after, groups_before)
        self.assertEqual(stale_retry[0]["title"], "Still mirrored")
        with self.assertRaises(V1WriteConflict):
            self.store.sync(0, [comic(updated=102)])
        _, rows = self.store.sync(0, [])
        self.assertEqual(rows[0]["title"], "Still mirrored")

    def test_v2_group_is_atomic_and_updates_flattened_v1_projection(self):
        request = v2_request(
            mutations=[
                mutation(
                    changes=[
                        change("custom_issue", "new", issue_data(title="Nova")),
                        change(
                            "collection_entry",
                            "new",
                            entry_data(
                                "new",
                                updated=1,
                                is_read=True,
                                is_duplicate=True,
                                rating=4,
                            ),
                        ),
                        change("copy", "copy-a", copy_data("new", updated=1)),
                        change(
                            "copy",
                            "copy-b",
                            copy_data(
                                "new",
                                updated=1,
                                ordinal=1,
                                condition_grade="G",
                            ),
                        ),
                    ]
                )
            ]
        )

        response = self.store.sync_v2(request)

        acknowledgement = response["acknowledgements"][0]
        self.assertEqual(acknowledgement["status"], "applied")
        self.assertEqual(acknowledgement["revision"], 1)
        self.assertEqual(response["change_groups"][0]["revision"], 1)
        self.assertEqual(len(response["change_groups"][0]["changes"]), 4)
        _, legacy = self.store.sync(0, [])
        flattened = legacy[0]
        self.assertEqual(flattened["title"], "Nova")
        self.assertEqual(flattened["is_read"], 1)
        self.assertEqual(flattened["is_duplicate"], 1)
        self.assertEqual(flattened["condition_grade"], "VF")
        self.assertEqual(flattened["rating"], 4)

    def test_concurrent_first_copies_converge_to_owned_and_duplicate(self):
        first = self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[
                            change("custom_issue", "one", issue_data()),
                            change(
                                "collection_entry",
                                "one",
                                entry_data(
                                    is_read=True,
                                    rating=4,
                                    notes="keep across copy changes",
                                ),
                            ),
                            change("copy", "device-a-copy", copy_data()),
                        ]
                    )
                ]
            )
        )
        second = self.store.sync_v2(
            v2_request(
                request_id="device-b-request",
                cursor=first["next_cursor"],
                mutations=[
                    mutation(
                        "device-b-mutation",
                        changes=[
                            change(
                                "copy",
                                "device-b-copy",
                                copy_data(ordinal=0, updated=1),
                            )
                        ],
                    )
                ],
            )
        )

        entry = next(
            item
            for item in second["change_groups"][0]["changes"]
            if item["entity_type"] == "collection_entry"
        )
        self.assertIs(entry["data"]["owned"], True)
        self.assertIs(entry["data"]["is_duplicate"], True)
        self.assertIs(entry["data"]["is_wanted"], False)
        self.assertIs(entry["data"]["is_read"], True)
        self.assertEqual(entry["data"]["rating"], 4)
        self.assertEqual(entry["data"]["notes"], "keep across copy changes")
        _, projection = self.store.sync(0, [])
        self.assertEqual(projection[0]["owned"], 1)
        self.assertEqual(projection[0]["is_duplicate"], 1)

    def test_unobserved_active_copy_wins_over_stale_collection_delete(self):
        first = self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[
                            change("custom_issue", "one", issue_data()),
                            change(
                                "collection_entry",
                                "one",
                                entry_data(
                                    is_read=True,
                                    rating=5,
                                    notes="server metadata",
                                ),
                            ),
                            change("copy", "remote-copy", copy_data()),
                        ]
                    )
                ]
            )
        )

        stale_delete = v2_request(
            request_id="stale-delete-request",
            cursor=first["next_cursor"],
            mutations=[
                mutation(
                    "stale-delete-mutation",
                    changes=[
                        change(
                            "collection_entry",
                            "one",
                            entry_data(
                                updated=50,
                                owned=False,
                                is_wanted=False,
                                is_read=False,
                                rating=0,
                                notes="stale metadata",
                                deleted=True,
                            ),
                            operation="delete",
                        )
                    ],
                )
            ],
        )

        response = self.store.sync_v2(stale_delete)

        self.assertEqual(response["acknowledgements"][0]["status"], "applied")
        canonical_group = response["change_groups"][0]
        self.assertEqual(canonical_group["mutation_id"], "stale-delete-mutation")
        self.assertEqual(len(canonical_group["changes"]), 1)
        canonical = canonical_group["changes"][0]
        self.assertEqual(canonical["operation"], "upsert")
        self.assertIs(canonical["data"]["deleted"], False)
        self.assertIs(canonical["data"]["owned"], True)
        self.assertIs(canonical["data"]["is_duplicate"], False)
        self.assertIs(canonical["data"]["is_wanted"], False)
        self.assertIs(canonical["data"]["is_read"], True)
        self.assertEqual(canonical["data"]["rating"], 5)
        self.assertEqual(canonical["data"]["notes"], "server metadata")
        self.assertEqual(canonical["data"]["updated_at"], 100)

        # Exact retries are byte-for-byte stable and never create another
        # revision, so the originating outbox can be cleared safely.
        self.assertEqual(self.store.sync_v2(deepcopy(stale_delete)), response)
        with closing(self.store.connect()) as db, db:
            entry = db.execute(
                "SELECT operation,data_json FROM v2_entities "
                "WHERE entity_type='collection_entry' AND entity_id='one'"
            ).fetchone()
            copy = db.execute(
                "SELECT operation,data_json FROM v2_entities "
                "WHERE entity_type='copy' AND entity_id='remote-copy'"
            ).fetchone()
            groups = db.execute(
                "SELECT COUNT(*) FROM v2_change_groups"
            ).fetchone()[0]
        self.assertEqual(entry["operation"], "upsert")
        self.assertIs(json.loads(entry["data_json"])["deleted"], False)
        self.assertEqual(copy["operation"], "upsert")
        self.assertIs(json.loads(copy["data_json"])["active"], True)
        self.assertEqual(groups, 2)
        _, projection = self.store.sync(0, [])
        self.assertEqual(projection[0]["owned"], 1)
        self.assertEqual(projection[0]["is_read"], 1)
        self.assertEqual(projection[0]["rating"], 5)

    def test_collection_delete_succeeds_after_observed_copies_are_deleted(self):
        first = self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[
                            change("custom_issue", "one", issue_data()),
                            change("collection_entry", "one", entry_data()),
                            change("copy", "known-copy", copy_data()),
                        ]
                    )
                ]
            )
        )
        response = self.store.sync_v2(
            v2_request(
                request_id="observed-delete-request",
                cursor=first["next_cursor"],
                mutations=[
                    mutation(
                        "observed-delete-mutation",
                        changes=[
                            change(
                                "collection_entry",
                                "one",
                                entry_data(
                                    owned=False,
                                    is_wanted=False,
                                    deleted=True,
                                ),
                                operation="delete",
                            ),
                            change(
                                "copy",
                                "known-copy",
                                copy_data(active=False, deleted=True),
                                operation="delete",
                            ),
                        ],
                    )
                ],
            )
        )

        changes = {
            change["entity_type"]: change
            for change in response["change_groups"][0]["changes"]
        }
        self.assertEqual(changes["collection_entry"]["operation"], "delete")
        self.assertIs(changes["collection_entry"]["data"]["owned"], False)
        self.assertEqual(changes["copy"]["operation"], "delete")
        _, projection = self.store.sync(0, [])
        self.assertEqual(projection[0]["deleted"], 1)
        self.assertEqual(projection[0]["owned"], 0)

    def test_large_collection_deletes_copies_before_the_entry_tombstone(self):
        copy_count = 501
        copy_ids = [f"large-copy-{index}" for index in range(copy_count)]
        first_seed_changes = [
            change("custom_issue", "one", issue_data()),
            change("collection_entry", "one", entry_data()),
            *[
                change("copy", copy_id, copy_data(ordinal=index))
                for index, copy_id in enumerate(copy_ids[:498])
            ],
        ]
        self.assertEqual(len(first_seed_changes), MAX_V2_TOTAL_CHANGES)
        first = self.store.sync_v2(
            v2_request(
                request_id="large-seed-request-1",
                mutations=[mutation("large-seed-1", changes=first_seed_changes)],
            )
        )
        second = self.store.sync_v2(
            v2_request(
                request_id="large-seed-request-2",
                cursor=first["next_cursor"],
                mutations=[
                    mutation(
                        "large-seed-2",
                        changes=[
                            change(
                                "copy",
                                copy_id,
                                copy_data(ordinal=index),
                            )
                            for index, copy_id in enumerate(
                                copy_ids[498:],
                                start=498,
                            )
                        ],
                    )
                ],
            )
        )

        # A protocol-sized first mutation tombstones copies only. The server
        # keeps the aggregate alive because one observed physical copy remains.
        first_delete_changes = [
            change(
                "copy",
                copy_id,
                copy_data(ordinal=index, active=False, deleted=True),
                operation="delete",
            )
            for index, copy_id in enumerate(copy_ids[:MAX_V2_TOTAL_CHANGES])
        ]
        first_delete = self.store.sync_v2(
            v2_request(
                request_id="large-delete-request-1",
                cursor=second["next_cursor"],
                mutations=[
                    mutation("large-delete-1", changes=first_delete_changes)
                ],
            )
        )
        interim_entry = next(
            item
            for item in first_delete["change_groups"][0]["changes"]
            if item["entity_type"] == "collection_entry"
        )
        self.assertEqual(interim_entry["operation"], "upsert")
        self.assertIs(interim_entry["data"]["owned"], True)
        self.assertIs(interim_entry["data"]["is_duplicate"], False)

        # The final mutation removes the last copy first and puts the aggregate
        # tombstone last. It therefore observes zero active copies and deletion
        # becomes canonical without exceeding any upload boundary.
        final_delete = self.store.sync_v2(
            v2_request(
                request_id="large-delete-request-2",
                cursor=first_delete["next_cursor"],
                mutations=[
                    mutation(
                        "large-delete-2",
                        changes=[
                            change(
                                "copy",
                                copy_ids[-1],
                                copy_data(
                                    ordinal=copy_count - 1,
                                    active=False,
                                    deleted=True,
                                ),
                                operation="delete",
                            ),
                            change(
                                "collection_entry",
                                "one",
                                entry_data(
                                    owned=False,
                                    is_wanted=False,
                                    deleted=True,
                                ),
                                operation="delete",
                            ),
                        ],
                    )
                ],
            )
        )

        final_group = final_delete["change_groups"][0]["changes"]
        self.assertEqual(final_group[-1]["entity_type"], "collection_entry")
        self.assertEqual(final_group[-1]["operation"], "delete")
        self.assertIs(final_group[-1]["data"]["deleted"], True)
        self.assertIs(final_group[-1]["data"]["owned"], False)
        self.assertIs(final_group[-1]["data"]["is_duplicate"], False)
        self.assertIs(final_group[-1]["data"]["is_wanted"], False)

        with closing(self.store.connect()) as db, db:
            entry = db.execute(
                "SELECT operation,data_json FROM v2_entities "
                "WHERE entity_type='collection_entry' AND entity_id='one'"
            ).fetchone()
            copies = db.execute(
                "SELECT operation,data_json FROM v2_entities "
                "WHERE entity_type='copy' AND issue_id='one'"
            ).fetchall()
        self.assertEqual(entry["operation"], "delete")
        self.assertIs(json.loads(entry["data_json"])["owned"], False)
        self.assertEqual(len(copies), copy_count)
        self.assertTrue(
            all(
                row["operation"] == "delete"
                and json.loads(row["data_json"])["deleted"] is True
                and json.loads(row["data_json"])["active"] is False
                for row in copies
            )
        )
        _, projection = self.store.sync(0, [])
        self.assertEqual(projection[0]["deleted"], 1)
        self.assertEqual(projection[0]["owned"], 0)
        self.assertEqual(projection[0]["is_duplicate"], 0)

    def test_existing_copy_cannot_move_to_another_issue(self):
        first = self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[
                            change("custom_issue", "one", issue_data()),
                            change("copy", "fixed-copy", copy_data()),
                        ]
                    )
                ]
            )
        )
        moving = v2_request(
            request_id="move-request",
            cursor=first["next_cursor"],
            mutations=[
                mutation(
                    "move-mutation",
                    changes=[
                        change("custom_issue", "two", issue_data(title="Two")),
                        change("copy", "fixed-copy", copy_data("two")),
                    ],
                )
            ],
        )

        with self.assertRaisesRegex(ValueError, "cannot move"):
            self.store.sync_v2(moving)

        with closing(self.store.connect()) as db, db:
            row = db.execute(
                "SELECT issue_id FROM v2_entities "
                "WHERE entity_type='copy' AND entity_id='fixed-copy'"
            ).fetchone()
            groups = db.execute("SELECT COUNT(*) FROM v2_change_groups").fetchone()[0]
        self.assertEqual(row["issue_id"], "one")
        self.assertEqual(groups, 1)

    def test_request_and_mutation_retries_are_durable_and_idempotent(self):
        request = v2_request()
        first = self.store.sync_v2(request)
        reopened = Store(self.path)
        self.assertEqual(reopened.server_id, first["server_id"])
        cached = reopened.sync_v2(deepcopy(request))
        self.assertEqual(cached, first)

        duplicate = self.store.sync_v2(
            v2_request(
                request_id="request-2",
                cursor=first["next_cursor"],
                mutations=[mutation()],
            )
        )
        self.assertEqual(duplicate["acknowledgements"][0]["status"], "duplicate")
        self.assertEqual(duplicate["acknowledgements"][0]["revision"], 1)
        self.assertEqual(duplicate["change_groups"], [])
        with closing(self.store.connect()) as db, db:
            self.assertEqual(
                db.execute("SELECT COUNT(*) FROM v2_change_groups").fetchone()[0],
                1,
            )

        reused_request = deepcopy(request)
        reused_request["limit"] = 1
        with self.assertRaisesRegex(ApiError, "request_id"):
            self.store.sync_v2(reused_request)
        reused_mutation = v2_request(
            request_id="request-3",
            cursor=1,
            mutations=[
                mutation(
                    changes=[
                        change("custom_issue", "one", issue_data(title="Changed"))
                    ]
                )
            ],
        )
        with self.assertRaisesRegex(ApiError, "mutation_id"):
            self.store.sync_v2(reused_mutation)

    def test_client_cannot_reuse_an_internal_history_mutation_id(self):
        self.store.sync(0, [comic()])
        with closing(self.store.connect()) as db, db:
            internal_id = db.execute(
                "SELECT mutation_id FROM v2_change_groups"
            ).fetchone()[0]

        request = v2_request(
            request_id="reserved-history-id",
            mutations=[mutation(internal_id)],
        )
        with self.assertRaises(ApiError) as raised:
            self.store.sync_v2(request)

        self.assertEqual(raised.exception.status, 409)
        self.assertEqual(raised.exception.code, "mutation_id_reused")
        with closing(self.store.connect()) as db, db:
            self.assertEqual(
                db.execute("SELECT COUNT(*) FROM v2_change_groups").fetchone()[0],
                1,
            )

    def test_invalid_later_mutation_rolls_back_the_entire_request(self):
        request = v2_request(
            mutations=[
                mutation("good"),
                mutation(
                    "bad",
                    changes=[
                        change(
                            "collection_entry",
                            "unknown",
                            entry_data("unknown"),
                        )
                    ],
                ),
            ]
        )

        with self.assertRaisesRegex(ValueError, "unknown issue_id"):
            self.store.sync_v2(request)

        with closing(self.store.connect()) as db, db:
            self.assertEqual(
                db.execute("SELECT COUNT(*) FROM v2_change_groups").fetchone()[0],
                0,
            )
            self.assertEqual(
                db.execute(
                    "SELECT value FROM sync_meta WHERE key='v2_activated'"
                ).fetchone()[0],
                "0",
            )

    def test_bundled_issue_hint_remains_fallback_data_not_custom_metadata(self):
        data = entry_data(
            "hinted", issue_hint=hint_data("hinted", title="Hinted")
        )
        response = self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[change("collection_entry", "hinted", data)]
                    )
                ]
            )
        )

        group = response["change_groups"][0]
        self.assertEqual(
            [item["entity_type"] for item in group["changes"]],
            ["collection_entry"],
        )
        self.assertEqual(
            group["changes"][0]["data"]["issue_hint"]["origin"],
            "bundled",
        )
        _, legacy = self.store.sync(0, [])
        self.assertEqual(legacy[0]["title"], "Hinted")

    def test_pagination_advances_only_through_returned_complete_groups(self):
        cursor = 0
        for index in range(3):
            response = self.store.sync_v2(
                v2_request(
                    request_id=f"write-{index}",
                    cursor=cursor,
                    mutations=[
                        mutation(
                            f"mutation-{index}",
                            changes=[
                                change(
                                    "custom_issue",
                                    f"issue-{index}",
                                    issue_data(title=f"Issue {index}"),
                                )
                            ],
                        )
                    ],
                )
            )
            cursor = response["next_cursor"]

        page1 = self.store.sync_v2(
            v2_request(request_id="page-1", cursor=0, limit=1, mutations=[])
        )
        page2 = self.store.sync_v2(
            v2_request(
                request_id="page-2",
                cursor=page1["next_cursor"],
                limit=1,
                mutations=[],
            )
        )
        page3 = self.store.sync_v2(
            v2_request(
                request_id="page-3",
                cursor=page2["next_cursor"],
                limit=1,
                mutations=[],
            )
        )

        self.assertTrue(page1["has_more"])
        self.assertTrue(page2["has_more"])
        self.assertFalse(page3["has_more"])
        self.assertEqual(
            [
                page1["change_groups"][0]["revision"],
                page2["change_groups"][0]["revision"],
                page3["change_groups"][0]["revision"],
            ],
            [1, 2, 3],
        )
        self.assertEqual(page3["next_cursor"], 3)

    def test_pagination_also_respects_the_encoded_response_byte_limit(self):
        cursor = 0
        for index in range(3):
            response = self.store.sync_v2(
                v2_request(
                    request_id=f"large-write-{index}",
                    cursor=cursor,
                    mutations=[
                        mutation(
                            f"large-mutation-{index}",
                            changes=[
                                change(
                                    "custom_issue",
                                    f"large-{index}",
                                    issue_data(title=(str(index) * 500)),
                                )
                            ],
                        )
                    ],
                )
            )
            cursor = response["next_cursor"]

        cap = 1500
        with mock.patch("comicollect_server.MAX_V2_RESPONSE_BYTES", cap):
            page = self.store.sync_v2(
                v2_request(
                    request_id="byte-page",
                    cursor=0,
                    limit=100,
                    mutations=[],
                )
            )

        self.assertTrue(page["change_groups"])
        self.assertTrue(page["has_more"])
        encoded = json.dumps(
            page, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        self.assertLessEqual(len(encoded), cap)

    def test_request_response_cache_is_bounded_by_encoded_bytes(self):
        cap = 1800
        cursor = 0
        with mock.patch("comicollect_server.MAX_V2_REQUEST_CACHE_BYTES", cap):
            for index in range(6):
                response = self.store.sync_v2(
                    v2_request(
                        request_id=f"cache-{index}",
                        cursor=cursor,
                        mutations=[
                            mutation(
                                f"cache-mutation-{index}",
                                changes=[
                                    change(
                                        "custom_issue",
                                        f"cache-issue-{index}",
                                        issue_data(title=str(index) * 200),
                                    )
                                ],
                            )
                        ],
                    )
                )
                cursor = response["next_cursor"]

        with closing(self.store.connect()) as db, db:
            total = db.execute(
                "SELECT COALESCE(SUM(LENGTH(CAST(response_json AS BLOB))+"
                "LENGTH(CAST(payload_hash AS BLOB))+"
                "LENGTH(CAST(request_id AS BLOB))),0) FROM v2_requests"
            ).fetchone()[0]
            newest = db.execute(
                "SELECT 1 FROM v2_requests WHERE request_id='cache-5'"
            ).fetchone()
        self.assertLessEqual(total, cap)
        self.assertIsNotNone(newest)

    def test_server_identity_cursor_and_client_clocks_are_not_ordering_sources(self):
        first = self.store.sync_v2(v2_request())
        older_client_clock = v2_request(
            request_id="older-clock",
            cursor=first["next_cursor"],
            server_id=first["server_id"],
            mutations=[
                mutation(
                    "older-mutation",
                    created_at=1,
                    changes=[
                        change(
                            "custom_issue",
                            "one",
                            issue_data(title="Server ordered"),
                        )
                    ],
                )
            ],
        )
        second = self.store.sync_v2(older_client_clock)
        self.assertGreater(
            second["acknowledgements"][0]["revision"],
            first["acknowledgements"][0]["revision"],
        )

        with self.assertRaisesRegex(ApiError, "server_id"):
            self.store.sync_v2(
                v2_request(
                    request_id="wrong-server",
                    cursor=2,
                    mutations=[],
                    server_id="another-server",
                )
            )
        with self.assertRaisesRegex(ApiError, "cursor"):
            self.store.sync_v2(
                v2_request(request_id="future", cursor=999, mutations=[])
            )

    def test_existing_v1_rows_bootstrap_exactly_once_on_reopen(self):
        self.store.sync(0, [comic()])
        with closing(self.store.connect()) as db, db:
            db.execute("DELETE FROM v2_entities")
            db.execute("DELETE FROM v2_change_groups")
            db.execute("DELETE FROM sqlite_sequence WHERE name='v2_change_groups'")
            db.execute(
                "UPDATE sync_meta SET value='0' WHERE key='v2_bootstrapped'"
            )

        reopened = Store(self.path)
        with closing(reopened.connect()) as db, db:
            first_count = db.execute(
                "SELECT COUNT(*) FROM v2_change_groups"
            ).fetchone()[0]
        Store(self.path)
        with closing(reopened.connect()) as db, db:
            second_count = db.execute(
                "SELECT COUNT(*) FROM v2_change_groups"
            ).fetchone()[0]
        self.assertEqual(first_count, 1)
        self.assertEqual(second_count, 1)

    def test_pre_index_v2_entities_gain_parent_column_backfill_and_index(self):
        self.store.sync_v2(
            v2_request(
                mutations=[
                    mutation(
                        changes=[
                            change("custom_issue", "one", issue_data()),
                            change("copy", "copy-one", copy_data()),
                        ]
                    )
                ]
            )
        )
        db = self.store.connect()
        try:
            db.execute("DROP INDEX idx_v2_entities_issue")
            db.execute("DROP INDEX idx_v2_entities_revision")
            db.execute("ALTER TABLE v2_entities RENAME TO v2_entities_new")
            db.execute("""CREATE TABLE v2_entities(
                entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
                operation TEXT NOT NULL, data_json TEXT NOT NULL,
                revision INTEGER NOT NULL,
                PRIMARY KEY(entity_type, entity_id)
            )""")
            db.execute(
                "INSERT INTO v2_entities "
                "SELECT entity_type,entity_id,operation,data_json,revision "
                "FROM v2_entities_new"
            )
            db.execute("DROP TABLE v2_entities_new")
            db.commit()
        finally:
            db.close()

        migrated = Store(self.path)
        with closing(migrated.connect()) as db, db:
            columns = {
                row[1] for row in db.execute("PRAGMA table_info(v2_entities)")
            }
            indexes = {
                row[1] for row in db.execute("PRAGMA index_list(v2_entities)")
            }
            parent = db.execute(
                "SELECT issue_id FROM v2_entities "
                "WHERE entity_type='copy' AND entity_id='copy-one'"
            ).fetchone()[0]
        self.assertIn("issue_id", columns)
        self.assertIn("idx_v2_entities_issue", indexes)
        self.assertEqual(parent, "one")

    def test_real_pre_v2_database_is_migrated_without_rewriting_v1_data(self):
        legacy_path = Path(self.tmp.name) / "legacy.sqlite3"
        db = sqlite3.connect(legacy_path)
        try:
            db.execute("""CREATE TABLE comics(
                id TEXT PRIMARY KEY, series TEXT NOT NULL, edition TEXT NOT NULL,
                number INTEGER NOT NULL, title TEXT NOT NULL,
                publisher TEXT NOT NULL DEFAULT '', year INTEGER,
                owned INTEGER NOT NULL, is_read INTEGER NOT NULL,
                condition_grade TEXT NOT NULL, purchase_price REAL,
                estimated_value REAL, is_duplicate INTEGER NOT NULL,
                loaned_to TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
                cover_asset TEXT NOT NULL DEFAULT '', rating INTEGER NOT NULL DEFAULT 0,
                page_count INTEGER, writer TEXT NOT NULL DEFAULT '',
                artist TEXT NOT NULL DEFAULT '', deleted INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL
            )""")
            value = validate_comic(comic())
            db.execute(
                f"INSERT INTO comics({','.join(FIELDS)}) "
                f"VALUES({','.join('?' for _ in FIELDS)})",
                [value[field] for field in FIELDS],
            )
            db.commit()
        finally:
            db.close()

        migrated = Store(legacy_path)

        _, legacy_rows = migrated.sync(0, [])
        self.assertEqual(legacy_rows[0]["title"], "Morgana")
        response = migrated.sync_v2(
            v2_request(request_id="legacy-first", mutations=[])
        )
        self.assertEqual(len(response["change_groups"]), 1)
        self.assertEqual(response["change_groups"][0]["mutation_id"].split(":")[0], "bootstrap")

    def test_odd_legacy_values_are_sanitized_into_reuploadable_v2_bounds(self):
        self.store.sync(
            0,
            [
                comic(
                    id="😀" * 64,
                    title="",
                    number=10**12,
                    year=99999,
                    page_count=-5,
                    notes="ž" * 10000,
                    purchase_price=float("nan"),
                )
            ],
        )

        response = self.store.sync_v2(
            v2_request(request_id="legacy-sanitize", mutations=[])
        )
        changes = response["change_groups"][0]["changes"]
        issue = next(item for item in changes if item["entity_type"] == "custom_issue")
        entry = next(
            item for item in changes if item["entity_type"] == "collection_entry"
        )
        primary = next(
            item
            for item in changes
            if item["entity_type"] == "copy" and item["data"]["ordinal"] == 0
        )
        self.assertTrue(issue["entity_id"].startswith("legacy-"))
        self.assertLessEqual(len(issue["entity_id"].encode()), 128)
        self.assertTrue(issue["data"]["title"])
        self.assertEqual(issue["data"]["number"], 10**9)
        self.assertIsNone(issue["data"]["year"])
        self.assertIsNone(issue["data"]["page_count"])
        self.assertLessEqual(len(entry["data"]["notes"].encode("utf-8")), 10000)
        self.assertIsNone(primary["data"]["purchase_price"])


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
        self.assertEqual(payload["ok"], True)
        self.assertEqual(payload["version"], 2)
        self.assertEqual(payload["protocols"], [1, 2])
        self.assertEqual(payload["records"], 0)
        self.assertEqual(payload["active"], 0)
        self.assertEqual(payload["server_id"], self.store.server_id)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertIn("Comicollect/2.0", headers["Server"])
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

    def test_v2_sync_uses_the_same_bearer_auth_and_exact_wire_contract(self):
        request = v2_request()
        self.assertEqual(
            self.request("POST", "/api/v2/sync", request)[0],
            401,
        )

        status, _, payload = self.request(
            "POST", "/api/v2/sync", request, headers=self.auth()
        )

        self.assertEqual(status, 200)
        self.assertEqual(
            set(payload),
            {
                "protocol",
                "server_id",
                "request_id",
                "server_time",
                "next_cursor",
                "has_more",
                "acknowledgements",
                "change_groups",
            },
        )
        self.assertEqual(payload["protocol"], 2)
        self.assertEqual(payload["request_id"], "request-1")
        self.assertEqual(payload["acknowledgements"][0]["status"], "applied")
        self.assertEqual(payload["change_groups"][0]["revision"], 1)

    def test_v2_validation_and_identity_conflicts_have_safe_http_errors(self):
        status, _, payload = self.request(
            "POST",
            "/api/v2/sync",
            v2_request(),
            headers={**self.auth(), "Content-Type": "text/plain"},
        )
        self.assertEqual(status, 415)
        self.assertEqual(payload["code"], "unsupported_media_type")

        status, _, payload = self.request(
            "POST",
            "/api/v2/sync",
            {**v2_request(), "cursor": "zero"},
            headers=self.auth(),
        )
        self.assertEqual(status, 400)
        self.assertIn("cursor", payload["error"])
        self.assertEqual(payload["code"], "invalid_request")

        status, _, first = self.request(
            "POST",
            "/api/v2/sync",
            v2_request(request_id="pin", mutations=[]),
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        status, _, payload = self.request(
            "POST",
            "/api/v2/sync",
            v2_request(
                request_id="wrong-pin",
                mutations=[],
                server_id="wrong-server",
            ),
            headers=self.auth(),
        )
        self.assertEqual(status, 409)
        self.assertEqual(payload["code"], "server_mismatch")
        self.assertEqual(first["server_id"], self.store.server_id)

        status, _, payload = self.request(
            "POST",
            "/api/v2/sync",
            raw=b"",
            headers={
                **self.auth(),
                "Content-Type": "application/json",
                "Content-Length": str(MAX_BODY + 1),
            },
        )
        self.assertEqual(status, 413)
        self.assertEqual(payload["code"], "request_too_large")

    def test_v1_writes_are_rejected_after_v2_activation_but_pulls_continue(self):
        self.store.sync(0, [comic()])
        status, _, _ = self.request(
            "POST",
            "/api/v2/sync",
            v2_request(request_id="activate"),
            headers=self.auth(),
        )
        self.assertEqual(status, 200)

        with closing(self.store.connect()) as db:
            current_updated_at = db.execute(
                "SELECT updated_at FROM comics WHERE id='one'"
            ).fetchone()[0]

        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 0, "changes": [comic(updated=current_updated_at + 1)]},
            headers=self.auth(),
        )
        self.assertEqual(status, 409)
        self.assertEqual(payload["code"], "v1_read_only")
        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 0, "changes": [comic()]},
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["changes"][0]["title"], "Morgana")
        status, _, payload = self.request(
            "POST",
            "/api/v1/sync",
            {"since": 0, "changes": []},
            headers=self.auth(),
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["changes"][0]["title"], "Morgana")

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
