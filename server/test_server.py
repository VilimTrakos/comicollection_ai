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
                "condition_grade":"VF", "is_duplicate":0, "deleted":0}

    def test_sync_and_newest_write_wins(self):
        _, rows = self.store.sync(0, [self.comic()])
        self.assertEqual(rows[0]["title"], "Morgana")
        self.store.sync(0, [self.comic(99, "Older")])
        _, rows = self.store.sync(0, [])
        self.assertEqual(rows[0]["title"], "Morgana")

    def test_validation_rejects_bad_grade(self):
        comic = self.comic(); comic["condition_grade"] = "BAD"
        with self.assertRaises(ValueError):
            validate_comic(comic)

    def test_backup(self):
        self.store.sync(0, [self.comic()])
        target = self.store.backup(Path(self.tmp.name) / "backups")
        self.assertTrue(target.exists())


if __name__ == "__main__":
    unittest.main()
