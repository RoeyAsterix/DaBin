#!/usr/bin/env python3
"""Create and exercise a local one-click update package for the current DaBin install."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_app import copy_permissions, copy_tree_without_metadata  # noqa: E402
from package_standalone import validate_app  # noqa: E402
from project_inventory import TARGET, build_inventory, fingerprint  # noqa: E402


def run(arguments, **kwargs):
    return subprocess.run([str(item) for item in arguments], check=True, **kwargs)


def output(arguments):
    return subprocess.check_output([str(item) for item in arguments], text=True, stderr=subprocess.STDOUT).strip()


def validate_updater(app):
    if app.is_symlink() or any(path.is_symlink() for path in app.rglob('*')):
        raise SystemExit('Refusing a symlink in the updater application')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.dabin.mac.updater.local':
        raise SystemExit('Unexpected updater identity')
    executable = app / 'Contents/MacOS/DaBinUpdate'
    if output(['lipo', '-archs', executable]) != 'arm64':
        raise SystemExit('Updater is not Apple Silicon ARM64')
    run(['codesign', '--verify', '--deep', '--strict', app])
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='New update ZIP; existing output is preserved')
    parser.add_argument('--guide', type=Path, help='Optional PDF guide to include')
    parser.add_argument('--release-manifest', type=Path,
                        help='Optional public DaBin-update.json written beside the verified ZIP')
    args = parser.parse_args()
    receipt = json.loads((ROOT / 'build/build-receipt.json').read_text())
    if receipt.get('configuration') != 'Release' or receipt.get('sourceFingerprint') != fingerprint(build_inventory()):
        raise SystemExit('The DaBin Release build receipt is stale. Rebuild before creating an update.')
    version = receipt['version']
    build_number = receipt['buildNumber']
    destination = (args.output or ROOT.parent / 'output/downloads' / f'DaBin-{version}-Update.zip').absolute()
    release_manifest = args.release_manifest.absolute() if args.release_manifest else None
    if destination.exists() or destination.is_symlink():
        raise SystemExit('Output exists; preserved: ' + str(destination))
    if release_manifest and (release_manifest.exists() or release_manifest.is_symlink()):
        raise SystemExit('Release manifest exists; preserved: ' + str(release_manifest))
    if args.guide and (not args.guide.is_file() or args.guide.is_symlink() or args.guide.suffix.lower() != '.pdf'):
        raise SystemExit('--guide must be a normal PDF file')

    source_app = ROOT / 'build/DaBin.app'

    with tempfile.TemporaryDirectory(prefix='dabin-update-package-') as temporary_name:
        temporary = Path(temporary_name)
        package = temporary / f'DaBin-{version}-Update'
        package.mkdir()
        packaged_app = package / 'DaBin.app'
        copy_tree_without_metadata(source_app, packaged_app)
        info, dependencies = validate_app(packaged_app)
        embedded_updater = packaged_app / 'Contents/Helpers/DaBin Update.app'
        embedded_updater_executable = validate_updater(embedded_updater)
        if info.get('DaBinSourceFingerprint') != receipt['sourceFingerprint']:
            raise SystemExit('Application and build receipt fingerprints do not match')

        updater = package / 'DaBin Update.app'
        executable = updater / 'Contents/MacOS/DaBinUpdate'
        resources = updater / 'Contents/Resources'
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        run(['xcrun', 'swiftc', '-swift-version', '5', '-target', TARGET,
             '-warnings-as-errors', '-O', '-whole-module-optimization', '-parse-as-library',
             ROOT / 'Sources/DaBin/UpdateHandoff.swift', ROOT / 'UpdateTools/DaBinUpdater.swift', '-o', executable])
        updater_info = {
            'CFBundleIdentifier': 'com.dabin.mac.updater.local',
            'CFBundleName': 'DaBin Update',
            'CFBundleDisplayName': 'DaBin Update',
            'CFBundleExecutable': 'DaBinUpdate',
            'CFBundleIconFile': 'AppIcon',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': build_number,
            'CFBundleShortVersionString': version,
            'NSPrincipalClass': 'NSApplication',
            'LSMinimumSystemVersion': '14.0',
            'NSHighResolutionCapable': True,
            'NSHumanReadableCopyright': '© 2026 DaBin',
            'CFBundleDocumentTypes': [{
                'CFBundleTypeName': 'DaBin Verified Update Request',
                'CFBundleTypeRole': 'Viewer',
                'LSHandlerRank': 'Owner',
                'LSItemContentTypes': ['com.dabin.update-request'],
            }],
            'UTExportedTypeDeclarations': [{
                'UTTypeIdentifier': 'com.dabin.update-request',
                'UTTypeDescription': 'DaBin Verified Update Request',
                'UTTypeConformsTo': ['public.json'],
                'UTTypeTagSpecification': {
                    'public.filename-extension': ['dabinupdate'],
                    'public.mime-type': ['application/vnd.dabin.update+json'],
                },
            }],
        }
        (updater / 'Contents/Info.plist').write_bytes(plistlib.dumps(updater_info))
        copy_permissions(ROOT / 'Resources/AppIcon.icns', resources / 'AppIcon.icns')
        run(['codesign', '--force', '--sign', '-', updater])
        updater_executable = validate_updater(updater)

        (package / 'README.txt').write_text(f'''DaBin {version} ({build_number}) installer for this Apple Silicon Mac\n\nDouble-click “DaBin Update.app”, then choose Install for a fresh copy or Update\nwhen DaBin is already installed. It will:\n\n1. Ask a running DaBin copy to quit normally.\n2. Verify the ARM64 Release application and its signature.\n3. Back up an existing app under ~/Applications/.DaBinBackups/.\n4. Install or replace ~/Applications/DaBin.app and verify the installed copy.\n5. Open DaBin on Daily.\n\nYour captures are stored separately in DaBin's sandbox container. The installer\ndoes not read, copy, move or delete that archive. If DaBin has an unsaved edit\nor removal in progress, finish it and run the installer again.\n\nThis locally ad-hoc signed installer is for the current Mac. It is not a Mac App\nStore installer, notarized public distribution or Apple-approved update channel.\nNo security setting should be disabled.\n''')
        if args.guide:
            copy_permissions(args.guide, package / 'DaBin-Quick-Guide.pdf')

        # Exercise the exact updater binary twice against an isolated destination:
        # first install, then update with backup. It never touches the user's app.
        qa_destination = temporary / 'qa-home/Applications/DaBin.app'
        qa_destination.parent.mkdir(parents=True)
        command = [updater_executable, '--destination', qa_destination,
                   '--non-interactive', '--no-launch']
        run(command)
        validate_app(qa_destination)
        run(command)
        validate_app(qa_destination)
        backups = list((qa_destination.parent / '.DaBinBackups').glob('*.app'))
        if len(backups) != 1:
            raise SystemExit('Updater QA did not preserve exactly one previous application')
        validate_app(backups[0])
        if hashlib.sha256((qa_destination / 'Contents/MacOS/DaBin').read_bytes()).hexdigest() != receipt['executableSHA256']:
            raise SystemExit('Updater QA installed unexpected executable bytes')

        files = sorted(path for path in package.rglob('*') if path.is_file())
        manifest = {
            'schemaVersion': 1,
            'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'version': version,
            'buildNumber': build_number,
            'architecture': 'arm64',
            'minimumMacOS': '14.0',
            'targetInstallation': '~/Applications/DaBin.app',
            'preservesArchive': True,
            'backsUpExistingApplication': True,
            'supportsInAppGitHubDownload': True,
            'localAdHocSigning': True,
            'appStoreApproved': False,
            'sourceFingerprint': receipt['sourceFingerprint'],
            'systemLibraries': dependencies,
            'updaterQA': {
                'verifySource': 'passed',
                'freshInstall': 'passed',
                'replacement': 'passed',
                'backup': 'passed',
                'installedSignature': 'passed',
                'installedExecutableHash': 'passed',
                'sandboxCompatibleDocumentHandoff': 'passed',
            },
            'files': {str(path.relative_to(package)): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in files},
        }
        (package / 'UPDATE-MANIFEST.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')

        staged_zip = temporary / destination.name
        with zipfile.ZipFile(staged_zip, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(package.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(temporary))
        extracted = temporary / 'extracted'
        with zipfile.ZipFile(staged_zip) as archive:
            if archive.testzip() is not None:
                raise SystemExit('Update ZIP integrity check failed')
            archive.extractall(extracted)
            for member in archive.infolist():
                (extracted / member.filename).chmod(stat.S_IMODE(member.external_attr >> 16))
        delivered = extracted / package.name
        validate_app(delivered / 'DaBin.app')
        delivered_updater = validate_updater(delivered / 'DaBin Update.app')
        delivered_embedded_updater = validate_updater(
            delivered / 'DaBin.app/Contents/Helpers/DaBin Update.app')
        verified = output([delivered_updater, '--verify-only'])
        if f'Verified DaBin {version} ({build_number})' not in verified:
            raise SystemExit('Extracted updater did not verify the delivered app')
        for name, expected in manifest['files'].items():
            if hashlib.sha256((delivered / name).read_bytes()).hexdigest() != expected:
                raise SystemExit('Update ZIP round-trip hash mismatch: ' + name)
        zip_sha256 = hashlib.sha256(staged_zip.read_bytes()).hexdigest()
        # Exercise the embedded helper's exact LaunchServices document handoff
        # against a second isolated destination. A sandboxed app cannot pass
        # OpenConfiguration.arguments, so package identity travels in this
        # one-use file while QA-only destination controls remain command args.
        downloaded_destination = temporary / 'downloaded-qa-home/Applications/DaBin.app'
        downloaded_destination.parent.mkdir(parents=True)
        handoff = temporary / f'DaBin-{version}-package-qa.dabinupdate'
        handoff.write_text(json.dumps({
            'schemaVersion': 1,
            'packageName': staged_zip.name,
            'packageSHA256': zip_sha256,
        }, sort_keys=True, separators=(',', ':')))
        handoff.chmod(0o600)
        run(['/usr/bin/open', '-W', '-n', '-a', delivered_embedded_updater, handoff, '--args',
             '--destination', downloaded_destination, '--non-interactive', '--no-launch'])
        if handoff.exists():
            raise SystemExit('Embedded updater did not consume its one-use handoff')
        validate_app(downloaded_destination)
        if receipt['sourceFingerprint'] != fingerprint(build_inventory()):
            raise SystemExit('DaBin source changed while packaging the update')
        destination.parent.mkdir(parents=True, exist_ok=True)
        with staged_zip.open('rb') as source, destination.open('xb') as target:
            shutil.copyfileobj(source, target)

        if release_manifest:
            public_manifest = {
                'schemaVersion': 1,
                'bundleIdentifier': 'com.dabin.mac',
                'version': version,
                'buildNumber': build_number,
                'architecture': 'arm64',
                'minimumMacOS': '14.0',
                'sourceFingerprint': receipt['sourceFingerprint'],
                'releasePageURL': f'https://github.com/RoeyAsterix/DaBin/releases/tag/v{version}',
                'asset': {
                    'name': destination.name,
                    'url': f'https://github.com/RoeyAsterix/DaBin/releases/download/v{version}/{destination.name}',
                    'bytes': destination.stat().st_size,
                    'sha256': zip_sha256,
                },
            }
            release_manifest.parent.mkdir(parents=True, exist_ok=True)
            with release_manifest.open('x') as stream:
                json.dump(public_manifest, stream, indent=2, sort_keys=True)
                stream.write('\n')

    print('Created and verified ' + str(destination))
    print('Updater QA passed fresh install, replacement, backup, signature and hash checks.')
    if release_manifest:
        print('Created GitHub update manifest ' + str(release_manifest))


if __name__ == '__main__':
    main()
