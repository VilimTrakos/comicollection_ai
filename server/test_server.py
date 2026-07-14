import tempfile
import unittest
from pathlib import Path
from comicollect_server import Store, validate_comic


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / "db.sqlite3")

    def tearDown(self):
        self.tmp.cleanup()

    def comic(self, updated=100, title="Morgana"):
        return {"id":"one", "series":"Dylan Dog", "edition":"Extra", "number":25,
                "title":title, "updated_at":updated, "owned":1, "is_read":0,
                "condition_grade":"VF", "is_duplicate":0, "deleted":0,
                "cover_asset":"assets/catalog/covers/ddlu/0061.webp"}

    def test_sync_and_newest_write_wins(self):
        _, rows = self.store.sync(0, [self.comic()])
        self.assertEqual(rows[0]["title"], "Morgana")
        self.assertEqual(rows[0]["cover_asset"], "assets/catalog/covers/ddlu/0061.webp")
        self.store.sync(0, [self.comic(99, "Older")])
        _, rows = self.store.sync(0, [])
        self.assertEqual(rows[0]["title"], "Morgana")

    def test_validation_rejects_bad_grade(self):
        comic = self.comic(); comic["condition_grade"] = "BAD"
        with self.assertRaises(ValueError):
            validate_comic(comic)

    def test_sync_keeps_issue_metadata(self):
        comic = self.comic()
        comic.update({
            "rating": 4,
            "page_count": 98,
            "writer": "Tiziano Sclavi",
            "artist": "Angelo Stano",
        })
        _, rows = self.store.sync(0, [comic])
        self.assertEqual(rows[0]["rating"], 4)
        self.assertEqual(rows[0]["page_count"], 98)
        self.assertEqual(rows[0]["writer"], "Tiziano Sclavi")
        self.assertEqual(rows[0]["artist"], "Angelo Stano")

    def test_backup(self):
        self.store.sync(0, [self.comic()])
        target = self.store.backup(Path(self.tmp.name) / "backups")
        self.assertTrue(target.exists())


if __name__ == "__main__":
    unittest.main()
