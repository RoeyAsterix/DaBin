"""Actual macOS directory transactions in disposable fixtures; no real install."""
import contextlib
import io
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import install_app


class LocalInstallTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='DaBinInstallSecurity-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def app(self, path, text):
        (path / 'Contents').mkdir(parents=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.dabin.mac'}))
        (path / 'Contents/Fixture').write_text(text)
        return path

    def test_atomic_move_preserves_existing_empty_directory(self):
        source = self.app(self.root / 'source.app', 'source')
        target = self.root / 'target.app'
        target.mkdir()
        before = install_app.directory_identity(target)
        with self.assertRaises(FileExistsError):
            install_app.rename_without_replacing(source, target)
        self.assertEqual(install_app.directory_identity(target), before)
        self.assertEqual((source / 'Contents/Fixture').read_text(), 'source')

    def test_atomic_move_preserves_dangling_symlink(self):
        source = self.app(self.root / 'source.app', 'source')
        target = self.root / 'target.app'
        target.symlink_to(self.root / 'missing.app')
        with self.assertRaises(FileExistsError):
            install_app.rename_without_replacing(source, target)
        self.assertTrue(target.is_symlink())
        self.assertTrue(source.is_dir())

    def test_successful_move_keeps_owned_identity(self):
        source = self.app(self.root / 'source.app', 'source')
        before = install_app.directory_identity(source)
        target = self.root / 'target.app'
        install_app.rename_without_replacing(source, target)
        self.assertEqual(install_app.directory_identity(target), before)
        self.assertFalse(source.exists())

    def run_failed_install(self, competing):
        source = self.app(self.root / 'build/DaBin.app', 'new')
        home = self.root / 'fictional-home'
        destination = self.app(home / 'Applications/DaBin.app', 'old')
        def validate(path):
            if path == destination:
                if competing:
                    shutil.rmtree(destination)
                    self.app(destination, 'competing')
                raise ValueError('synthetic verification failure')
        with mock.patch.object(install_app, 'ROOT', self.root), \
             mock.patch.object(install_app.Path, 'home', return_value=home), \
             mock.patch.object(install_app, 'verify', side_effect=validate), \
             mock.patch.object(install_app.subprocess, 'check_output', return_value=''), \
             contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'synthetic verification failure'):
                install_app.main()
        self.assertEqual((source / 'Contents/Fixture').read_text(), 'new')
        return home, destination

    def test_verification_failure_restores_owned_previous_app(self):
        home, destination = self.run_failed_install(False)
        self.assertEqual((destination / 'Contents/Fixture').read_text(), 'old')
        self.assertFalse(list((home / 'Applications').glob('.DaBin-install-*')))

    def test_rollback_preserves_competing_app_and_previous_backup(self):
        home, destination = self.run_failed_install(True)
        self.assertEqual((destination / 'Contents/Fixture').read_text(), 'competing')
        backups = list((home / 'Applications/.DaBinBackups').glob('*.app'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'Contents/Fixture').read_text(), 'old')


if __name__ == '__main__':
    unittest.main()
