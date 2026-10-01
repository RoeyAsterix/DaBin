"""Offline metadata gates. All mutations are disposable JSON fixtures."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("store_metadata", ROOT / "scripts/validate_app_store_metadata.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class StoreMetadataTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(validator.DEFAULT.read_text())
        self.temp = tempfile.TemporaryDirectory(prefix="DaBinMetadataQA-")
        self.path = Path(self.temp.name) / "metadata.json"

    def tearDown(self):
        self.temp.cleanup()

    def validate(self, strict=False):
        self.path.write_text(json.dumps(self.fixture), encoding="utf-8")
        return validator.validate(self.path, strict)

    def test_current_copy_constraints(self):
        result = self.validate()
        self.assertEqual(result["errors"], [])
        self.assertFalse(result["submissionReady"])

    def test_current_draft_is_not_submission_complete(self):
        result = self.validate(strict=True)
        self.assertTrue(result["errors"])
        self.assertIn("all externally verified submission gates are resolved", result["errors"])

    def test_name_limit(self):
        self.fixture["productPage"]["name"] = "x" * 31
        self.assertIn("name contains 1-30 characters", self.validate()["errors"])

    def test_subtitle_limit(self):
        self.fixture["productPage"]["subtitle"] = "x" * 31
        self.assertIn("subtitle contains 1-30 characters", self.validate()["errors"])

    def test_promo_limit(self):
        self.fixture["productPage"]["promotionalText"] = "x" * 171
        self.assertIn("promotionalText contains 1-170 characters", self.validate()["errors"])

    def test_description_limit(self):
        self.fixture["productPage"]["description"] = "x" * 4001
        self.assertIn("description contains 1-4000 characters", self.validate()["errors"])

    def test_description_boundary(self):
        self.fixture["productPage"]["description"] = "x" * 4000
        self.assertEqual(self.validate()["errors"], [])

    def test_empty_description(self):
        self.fixture["productPage"]["description"] = ""
        self.assertIn("description contains 1-4000 characters", self.validate()["errors"])

    def test_keywords_are_measured_in_utf8_bytes(self):
        self.fixture["productPage"]["keywords"] = "日本語" * 12
        self.assertIn("keywords fit Apple's 100-byte limit", self.validate()["errors"])

    def test_short_keywords_rejected(self):
        self.fixture["productPage"]["keywords"] = "file,AI"
        self.assertIn("each keyword is longer than two characters", self.validate()["errors"])

    def test_review_notes_are_measured_in_utf8_bytes(self):
        self.fixture["review"]["notes"] = "日" * 1334
        self.assertIn("review notes fit Apple's 4000-byte limit", self.validate()["errors"])

    def test_source_version_mismatch(self):
        self.fixture["candidate"]["version"] = "999.0"
        self.assertIn("candidate version matches source Info.plist", self.validate()["errors"])

    def test_source_bundle_mismatch(self):
        self.fixture["candidate"]["bundleIdentifier"] = "com.invalid.fixture"
        self.assertIn("candidate bundleIdentifier matches source Info.plist", self.validate()["errors"])

    def test_plain_text_description(self):
        self.fixture["productPage"]["description"] = "<b>Not supported</b>"
        self.assertIn("description is plain text, without HTML", self.validate()["errors"])

    def test_owner_fields_never_imply_apple_approval(self):
        self.fixture["productPage"]["supportURL"] = "https://support.test.invalid"
        self.fixture["productPage"]["copyright"] = "2026 Fictional rights holder"
        self.fixture["review"].update(contactName="Fixture", contactEmail="fixture@test.invalid", contactPhone="+10000000000")
        self.fixture["ownerDecisions"] = {key: "fixture" for key in self.fixture["ownerDecisions"]}
        self.fixture["ownerDecisions"]["price"] = 0
        self.fixture["pendingGates"] = []
        result = self.validate(strict=True)
        self.assertEqual(result["errors"], [])
        self.assertFalse(result["submissionReady"])


if __name__ == "__main__":
    unittest.main()
