import unittest

from tools.import_bsp_catalog import catalog_metadata_signature


class CatalogMetadataSignatureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = {
            "catalogVersion": 1,
            "editions": ["DDLU"],
            "issues": [
                {
                    "id": "catalog-DDLU-61",
                    "sourceEdition": "DDLU",
                    "series": "Dylan Dog",
                    "edition": "Regularna (L)",
                    "number": 61,
                    "title": "Nesmiljeni Hook",
                    "publisher": "Ludens",
                    "year": 2002,
                    "coverAsset": "old.webp",
                    "visualHash": "old-hash",
                }
            ],
        }

    def test_ignores_version_and_derived_cover_data(self) -> None:
        rebuilt = {
            **self.payload,
            "catalogVersion": 8,
            "issues": [
                {
                    **self.payload["issues"][0],
                    "coverAsset": "new.webp",
                    "visualHash": "new-hash",
                }
            ],
        }

        self.assertEqual(
            catalog_metadata_signature(self.payload),
            catalog_metadata_signature(rebuilt),
        )

    def test_detects_metadata_and_membership_changes(self) -> None:
        renamed = {
            **self.payload,
            "issues": [{**self.payload["issues"][0], "title": "Novi naslov"}],
        }
        removed = {**self.payload, "issues": []}

        self.assertNotEqual(
            catalog_metadata_signature(self.payload),
            catalog_metadata_signature(renamed),
        )
        self.assertNotEqual(
            catalog_metadata_signature(self.payload),
            catalog_metadata_signature(removed),
        )

    def test_rejects_malformed_payloads(self) -> None:
        self.assertIsNone(catalog_metadata_signature(None))
        self.assertIsNone(catalog_metadata_signature({"issues": []}))
        self.assertIsNone(
            catalog_metadata_signature({"editions": [], "issues": [None]})
        )


if __name__ == "__main__":
    unittest.main()
