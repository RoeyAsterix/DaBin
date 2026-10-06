#!/usr/bin/env python3
"""Render fictional native review screenshots only after coordinated Store QA."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

from release_inputs import ROOT, add_release_arguments, digest, read_release, verify_unchanged

HERE = Path(__file__).resolve().parent
FILENAMES = ['DABIN__APP_STORE__01_INBOX.png', 'DABIN__APP_STORE__02_PROJECTS.png',
             'DABIN__APP_STORE__03_FOCUS.png']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_release_arguments(parser)
    parser.add_argument('--render', action='store_true', required=True,
                        help='Explicitly allow native fixture compilation and rendering after coordinated QA')
    parser.add_argument('--output-dir', type=Path,
                        help='New screenshot directory; defaults to docs/app-store/screenshots/VERSION-BUILD')
    args = parser.parse_args()
    release = read_release(args)
    native, inventory = release['native'], release['inventory']
    output = (args.output_dir or ROOT / f"docs/app-store/screenshots/{release['version']}-{release['build']}").resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit('Output directory is not empty. Preserve reviewed/older sets; use a new directory for each render iteration.')
    output.mkdir(parents=True, exist_ok=True)
    destination = ROOT / f"tmp/app-store-assets/{release['version']}-{release['build']}/screenshots"
    destination.mkdir(parents=True, exist_ok=True)
    for resource in inventory.resources():
        shutil.copyfile(resource, destination / resource.name)
    executable = destination / 'ExportScreenshots'
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', inventory.TARGET,
        '-module-cache-path', str(destination / 'ModuleCache'), '-warnings-as-errors', '-O',
        '-parse-as-library', '-I', str(release['moduleCache']), '-L', str(release['moduleCache']),
        '-lDaBinTestCore', '-Xlinker', '-rpath', '-Xlinker', str(release['moduleCache']),
        str(HERE / 'ExportScreenshots.swift'), '-o', str(executable)]
    subprocess.run(command, cwd=ROOT, check=True)
    subprocess.run([str(executable), str(output), release['version'], release['build']],
                   cwd=ROOT, check=True, timeout=90)
    verify_unchanged(release)
    from PIL import Image
    screenshots = []
    for filename in FILENAMES:
        path = output / filename
        with Image.open(path) as rendered:
            if rendered.size != (1440, 900) or rendered.mode not in ('RGB', 'RGBA'):
                raise SystemExit(f'Wrong screenshot dimensions/color: {filename}')
            rendered.load()
            if rendered.mode == 'RGBA' and rendered.getchannel('A').getextrema() != (255, 255):
                raise SystemExit(f'Nonopaque native canvas: {filename}')
            rgb = rendered.convert('RGB')
            if all(high - low < 30 for low, high in rgb.getextrema()):
                raise SystemExit(f'Blank native fixture: {filename}')
        rgb.save(path, 'PNG')
        with Image.open(path) as rendered:
            if rendered.mode != 'RGB' or 'transparency' in rendered.info:
                raise SystemExit(f'Opaque RGB verification failed: {filename}')
            rendered.verify()
        screenshots.append({'file': filename, 'sha256': digest(path), 'width': 1440, 'height': 900,
                            'colorMode': 'RGB', 'alpha': False})
    manifest = {
        'schemaVersion': 2, 'version': release['version'], 'build': release['build'],
        'distribution': 'app-store', 'nativeRoot': str(native.relative_to(ROOT)),
        'status': 'DRAFT_NOT_VERIFIED_AGAINST_DISTRIBUTION_BINARY',
        'dimensions': [1440, 900], 'colorMode': 'RGB', 'alpha': False,
        'fixturePrivacy': 'Fictional temporary archive, isolated preferences, non-key offscreen windows; no personal data, clipboard, network, notifications, permissions, global input or installed-app actions.',
        'renderMethod': 'Production native BoardView/RobotAppFrameView/RobotCharacterView at 1x; backdrop/headlines are marketing composition.',
        'sourceSHA256': release['sources'], 'resourceSHA256': release['resources'],
        'infoSHA256': release['infoSHA256'], 'exportSourceSHA256': digest(HERE / 'ExportScreenshots.swift'),
        'exportScriptSHA256': digest(Path(__file__)), 'releaseInputVerifierSHA256': digest(HERE / 'release_inputs.py'),
        'verifiedModuleReceipt': str(release['moduleStamp'].relative_to(native)) if release['moduleStamp'].is_relative_to(native) else str(release['moduleStamp']),
        'verifiedModuleReceiptSHA256': digest(release['moduleStamp']),
        'moduleOutputs': release['moduleReceipt']['outputs'], 'compilerArguments': command,
        'nativeRenderManifest': 'native-renders.json', 'nativeRenderManifestSHA256': digest(output / 'native-renders.json'),
        'screenshots': screenshots, 'visualReview': 'Pending inspection of all three original-resolution images.',
        'submissionGate': 'Compare with the exact distribution-signed app and confirm rights before any separately authorized upload.'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    (output / 'README.md').write_text(f"# DaBin {release['version']} ({release['build']}) screenshot drafts\n\n"
        'Three 1440 × 900 opaque RGB PNGs show actual native Store-channel views with fictional records.\n\n'
        + '\n'.join(f'- [{name}]({name})' for name in FILENAMES) + '\n\n'
        '**Visual inspection pending.** These local drafts require comparison with the exact distribution-signed app and owner artwork-rights confirmation. No upload or submission performed.\n')
    print(output)


if __name__ == '__main__':
    main()
