#!/usr/bin/env python3
"""Package only the Release ARM64 app and explicit documentation, never a user archive."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import zipfile
from project_inventory import ROOT, build_inventory, fingerprint
from build_app import copy_permissions, copy_tree_without_metadata


def output(arguments):
    return subprocess.check_output([str(item) for item in arguments], text=True, stderr=subprocess.STDOUT).strip()


def validate_app(app):
    if app.is_symlink() or any(path.is_symlink() for path in app.rglob('*')):
        raise SystemExit('Refusing a symlink in the standalone application')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.dabin.mac' or info.get('DaBinBuildConfiguration') != 'Release':
        raise SystemExit('Packaging requires the DaBin Release build')
    if info.get('LSMinimumSystemVersion') != '14.0':
        raise SystemExit('Unexpected minimum system version')
    executable = app / 'Contents/MacOS/DaBin'
    if output(['lipo', '-archs', executable]) != 'arm64':
        raise SystemExit('Packaging requires an Apple Silicon ARM64-only binary')
    for name in ('robot.svg', 'AppIcon.icns', 'PrivacyInfo.xcprivacy', 'PrivacyPolicy.md'):
        if not (app / 'Contents/Resources' / name).is_file():
            raise SystemExit('Required resource is missing: ' + name)
    dependencies = [line.strip().split(' (compatibility', 1)[0] for line in output(['otool', '-L', executable]).splitlines()[1:]]
    if any(not name.startswith(('/System/Library/', '/usr/lib/')) for name in dependencies):
        raise SystemExit('Standalone binary links to a non-system library; review its packaging')
    if any(path.suffix == '.dSYM' for path in app.rglob('*')):
        raise SystemExit('Debug symbols belong outside the application')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    return info, dependencies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='New ZIP file path; existing files are preserved')
    parser.add_argument('--guide', type=Path, help='Optional explicit PDF guide to include')
    args = parser.parse_args()
    source = ROOT / 'build/DaBin.app'
    receipt = json.loads((ROOT / 'build/build-receipt.json').read_text())
    if receipt.get('configuration') != 'Release' or receipt.get('sourceFingerprint') != fingerprint(build_inventory()):
        raise SystemExit('Build receipt is stale or not Release. Rebuild before packaging.')
    version = receipt['version']
    destination = args.output or ROOT.parent / 'output/downloads' / f'DaBin-{version}-AppleSilicon.zip'
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise SystemExit('Output exists; preserve or move it before packaging: ' + str(destination))
    if args.guide and (args.guide.suffix.lower() != '.pdf' or not args.guide.is_file() or args.guide.is_symlink()):
        raise SystemExit('--guide must point to a readable PDF file')
    with tempfile.TemporaryDirectory(prefix='dabin-package-') as temporary:
        temporary = Path(temporary)
        package = temporary / f'DaBin-{version}-AppleSilicon'
        package.mkdir()
        app = package / 'DaBin.app'
        if source.is_symlink() or any(path.is_symlink() for path in source.rglob('*')):
            raise SystemExit('Refusing a symlink in the source application')
        copy_tree_without_metadata(source, app)
        info, dependencies = validate_app(app)
        if info.get('DaBinSourceFingerprint') != receipt['sourceFingerprint'] or hashlib.sha256((app / 'Contents/MacOS/DaBin').read_bytes()).hexdigest() != receipt['executableSHA256']:
            raise SystemExit('App bytes do not match the build receipt')
        signature = output(['codesign', '-d', '--verbose=4', app])
        local_signing = 'Signature=adhoc' in signature
        (package / 'README.txt').write_text(f'''DaBin {version} for Apple Silicon\n\nRequires an Apple Silicon Mac with macOS 14 or later.\nMove DaBin.app to ~/Applications (your home Applications folder), then open it.\nKeep this as your only DaBin.app so future in-app updates replace the same copy.\n\nMove your pointer into a screen corner to reveal the robot. Drop files, images,\nlinks or text onto it; while hovering, use Command-V or Control-V to paste.\nDouble-click the robot to open your day. The daily board also accepts drops\nand paste. Use + for a task, the checkmark filter for tasks, and Comment or\nReminder on a capture. The 1 / 7 calendar buttons switch Daily and Weekly.\n\nYour captures and copies of files stay on this Mac. The app creates its managed\narchive in its sandbox container; no personal captures are included in this ZIP.\nWebsite preview fetching is optional and contacts the site you choose.\n\nBuild status: optimized Release, ARM64.\nSigning: {'local ad-hoc' if local_signing else 'see code-signing identity on app'}.\nThis package has not been notarized or approved by the Mac App Store. macOS\nmay prevent opening it on another Mac; a publicly distributed release needs\nApple signing and distribution validation. No security settings should be disabled.\n''')
        if args.guide:
            copy_permissions(args.guide, package / 'DaBin-Quick-Guide.pdf')
        files = sorted(path for path in package.rglob('*') if path.is_file())
        manifest = {'schemaVersion': 1, 'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'version': version, 'buildNumber': info['CFBundleVersion'], 'configuration': 'Release',
                    'architecture': 'arm64', 'minimumMacOS': '14.0',
                    'installationTarget': '~/Applications/DaBin.app', 'localAdHocSigning': local_signing,
                    'appStoreApproved': False, 'notarizationValidated': False,
                    'sourceFingerprint': receipt['sourceFingerprint'], 'systemLibraries': dependencies,
                    'files': {str(path.relative_to(package)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}}
        (package / 'PACKAGE-MANIFEST.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        staged_zip = temporary / destination.name
        with zipfile.ZipFile(staged_zip, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(package.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(temporary))
        extracted = temporary / 'extracted'
        with zipfile.ZipFile(staged_zip) as archive:
            if archive.testzip():
                raise SystemExit('ZIP integrity check failed')
            archive.extractall(extracted)
            for member in archive.infolist():
                mode = member.external_attr >> 16
                (extracted / member.filename).chmod(stat.S_IMODE(mode))
        delivered = extracted / package.name
        validate_app(delivered / 'DaBin.app')
        for name, expected in manifest['files'].items():
            if hashlib.sha256((delivered / name).read_bytes()).hexdigest() != expected:
                raise SystemExit('ZIP round-trip hash mismatch')
        if receipt.get('sourceFingerprint') != fingerprint(build_inventory()):
            raise SystemExit('Source changed while packaging; rebuild before delivery')
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation prevents a late race from overwriting another artifact.
        with staged_zip.open('rb') as src, destination.open('xb') as dst:
            shutil.copyfileobj(src, dst)
    print(f'Created and verified {destination}')
    print('Contains the app and documentation only. Apple distribution approval remains pending.')

if __name__ == '__main__':
    main()
