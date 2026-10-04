"""Offline archive destination guards, using only disposable directory fixtures."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/app_store_archive_location.py"
SPEC = importlib.util.spec_from_file_location("dabin_archive_location", SCRIPT)
assert SPEC and SPEC.loader
location = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(location)


class ArchiveLocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="DaBinArchiveLocationQA-")
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        # Path-policy tests must not inspect unrelated ancestor metadata or
        # depend on the host's File Provider configuration.
        self.attribute_probe = mock.patch.object(location, "file_provider_attribute", return_value=None)
        self.attribute_probe.start()

    def tearDown(self):
        self.attribute_probe.stop()
        self.temporary.cleanup()

    def test_new_external_archive_is_accepted_without_creating_it(self):
        destination = self.root / "archives" / "DaBin.xcarchive"
        self.assertEqual(location.validate(destination, self.project), destination)
        self.assertFalse(destination.parent.exists())

    def test_nested_missing_external_parents_are_accepted(self):
        destination = self.root / "archives" / "new" / "day" / "DaBin.xcarchive"
        self.assertEqual(location.validate(destination, self.project), destination)
        self.assertFalse(destination.parent.exists())

    def test_existing_destination_is_preserved_and_refused(self):
        destination = self.root / "DaBin.xcarchive"
        destination.mkdir()
        with self.assertRaisesRegex(ValueError, "already exists"):
            location.validate(destination, self.project)
        self.assertTrue(destination.is_dir())

    def test_direct_source_tree_destination_is_refused(self):
        destination = self.project / "new" / "DaBin.xcarchive"
        with self.assertRaisesRegex(ValueError, "outside the source repository"):
            location.validate(destination, self.project)

    def test_parent_traversal_after_existing_component_is_refused(self):
        existing = self.root / "archives"
        existing.mkdir()
        destination = existing / ".." / "project" / "DaBin.xcarchive"
        with self.assertRaisesRegex(ValueError, "parent-directory traversal"):
            location.validate(destination, self.project)
        self.assertFalse((self.project / "DaBin.xcarchive").exists())

    def test_parent_traversal_after_missing_component_is_refused(self):
        for trailing_parent in ("project", "other-external"):
            with self.subTest(trailing_parent=trailing_parent):
                destination = self.root / "not-created" / ".." / trailing_parent / "DaBin.xcarchive"
                with self.assertRaisesRegex(ValueError, "parent-directory traversal"):
                    location.validate(destination, self.project)
        self.assertFalse((self.root / "not-created").exists())
        self.assertFalse((self.project / "DaBin.xcarchive").exists())

    def test_symlink_parent_is_refused(self):
        external = self.root / "external"
        external.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symbolic-link"):
            location.validate(alias / "DaBin.xcarchive", self.project)

    def test_dots_inside_an_ordinary_filename_are_not_traversal(self):
        destination = self.root / "archives" / "DaBin..beta.xcarchive"
        self.assertEqual(location.validate(destination, self.project), destination)


if __name__ == "__main__":
    unittest.main(verbosity=2)
