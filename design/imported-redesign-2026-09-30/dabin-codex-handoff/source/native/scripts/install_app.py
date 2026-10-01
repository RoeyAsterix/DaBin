#!/usr/bin/env python3
"""Install a verified local app with a backup, rollback and a running-app guard."""
from pathlib import Path
import datetime
import plistlib
import shutil
import subprocess
import uuid
from build_app import copy_permissions, copy_tree_without_metadata
from project_inventory import ROOT


def verify(app):
    if app.is_symlink() or any(path.is_symlink() for path in app.rglob('*')):
        raise SystemExit('A symlink is present in an app path; installation was not attempted')
    if plistlib.loads((app / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != 'com.dabin.mac':
        raise SystemExit('Unexpected app identity; preserved')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


def main():
    source = ROOT / 'build/DaBin.app'
    applications = Path.home() / 'Applications'
    destination = applications / 'DaBin.app'
    if applications.is_symlink() or destination.is_symlink():
        raise SystemExit('Refusing a symlink destination; preserved')
    if destination.exists() and plistlib.loads((destination / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != 'com.dabin.mac':
        raise SystemExit('An unrelated destination exists; preserved')
    # Check only executable command paths, never process arguments or user data.
    commands = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
    if any(command.strip().endswith('/DaBin.app/Contents/MacOS/DaBin') for command in commands):
        raise SystemExit('Quit DaBin before installing so the current process cannot retain an older app bundle.')
    applications.mkdir(exist_ok=True)
    staging = applications / ('.DaBin-install-' + str(uuid.uuid4()) + '.app')
    backup = None
    installed = False
    try:
        if source.is_symlink() or any(path.is_symlink() for path in source.rglob('*')):
            raise SystemExit('Refusing a symlink in the source app')
        copy_tree_without_metadata(source, staging)
        verify(staging)
        if destination.exists():
            backups = applications / '.DaBinBackups'
            if backups.is_symlink():
                raise SystemExit('Refusing a symlink backup directory')
            backups.mkdir(exist_ok=True)
            backup = backups / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + str(uuid.uuid4())[:8] + '.app')
            destination.rename(backup)
        staging.rename(destination)
        installed = True
        verify(destination)
    except BaseException:
        if installed and destination.exists():
            destination.rename(staging)
        if backup and backup.exists():
            backup.rename(destination)
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    if backup:
        print('Previous app preserved at ' + str(backup))
    print('Installed ' + str(destination))
    print('Your archive was not modified. Open DaBin to use the installed version.')

if __name__ == '__main__':
    main()
