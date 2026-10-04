#!/usr/bin/env python3
"""Export fictional guide UI from an explicitly selected, hash-verified QA module."""
import argparse
import hashlib
import importlib.util
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-root', type=Path, default=ROOT / 'native',
                        help='Production source root. Select a verified frozen candidate explicitly.')
    parser.add_argument('--module-cache', type=Path,
                        help='Exact QA cache directory; otherwise choose the newest matching receipt.')
    parser.add_argument('--distribution', choices=['direct', 'app-store'], default='direct')
    args = parser.parse_args()
    native = args.native_root.resolve()
    # Import the inventory from the chosen root, never from the changing workspace.
    spec = importlib.util.spec_from_file_location('guide_project_inventory', native / 'scripts/project_inventory.py')
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    current_sources = inventory.hashes(inventory.sources(False))
    current_resources = inventory.hashes(inventory.resources())
    info_path = native / 'Resources/Info.plist'
    info_hash = digest(info_path)
    info = plistlib.loads(info_path.read_bytes())
    copy = json.loads((HERE / 'copy.json').read_text())
    if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (copy['version'], copy['build']):
        raise SystemExit('Copy version/build must match the explicitly selected native source.')
    stamps = [args.module_cache.resolve() / 'module-ready.json'] if args.module_cache else (native / 'build/qa-cache').glob('*/module-ready.json')
    verified = []
    expected_definitions = ['DABIN_DIRECT_UPDATES'] if args.distribution == 'direct' else []
    for stamp in stamps:
        try:
            receipt = json.loads(stamp.read_text())
            inputs = receipt['inputs']
            if (inputs['sources'] != current_sources or inputs['configuration'] != 'Release'
                    or inputs.get('distribution', 'direct') != args.distribution
                    or inputs.get('compileDefinitions', ['DABIN_DIRECT_UPDATES']) != expected_definitions
                    or inputs['target'] != inventory.TARGET):
                continue
            if set(receipt['outputs']) != {'DaBinTestCore.swiftmodule', 'libDaBinTestCore.dylib'}:
                continue
            if all(digest(stamp.parent / name) == sha for name, sha in receipt['outputs'].items()):
                verified.append((stamp.stat().st_mtime, stamp, receipt))
        except (OSError, KeyError, ValueError):
            continue
    if not verified:
        raise SystemExit('No matching hash-verified Release QA module for the selected source and channel.')
    _, stamp, receipt = max(verified, key=lambda item: item[0])
    cache = stamp.parent
    destination = native / 'build/guide-export'
    destination.mkdir(parents=True, exist_ok=True)
    for resource in inventory.resources():
        shutil.copyfile(resource, destination / resource.name)
    executable = destination / 'ExportGuide'
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', inventory.TARGET,
        '-module-cache-path', str(native / 'build/ModuleCache'), '-warnings-as-errors', '-O',
        *[value for flag in expected_definitions for value in ('-D', flag)],
        '-parse-as-library', '-I', str(cache), '-L', str(cache), '-lDaBinTestCore',
        '-Xlinker', '-rpath', '-Xlinker', str(cache), str(HERE / 'ExportGuide.swift'), '-o', str(executable)]
    subprocess.run(command, cwd=native, check=True)
    output = HERE / 'assets'
    subprocess.run([str(executable), str(output)], cwd=native, check=True, timeout=90)
    if (inventory.hashes(inventory.sources(False)) != current_sources
            or inventory.hashes(inventory.resources()) != current_resources or digest(info_path) != info_hash):
        raise SystemExit('Production inputs changed during export; reject these guide assets.')
    manifest = {
        'schemaVersion': 2, 'version': copy['version'], 'build': copy['build'],
        'nativeRoot': str(native.relative_to(ROOT)),
        'nativeRootSelection': 'explicit frozen source' if native != ROOT / 'native' else 'workspace source',
        'distribution': args.distribution,
        'fixturePrivacy': 'Fictional native UI only; local export, no installed-app or personal-data access.',
        'sourceSHA256': current_sources, 'resourceSHA256': current_resources, 'infoSHA256': info_hash,
        'exportSourceSHA256': digest(HERE / 'ExportGuide.swift'),
        'exportScriptSHA256': digest(Path(__file__)),
        'verifiedModuleReceipt': str(stamp.relative_to(native)), 'verifiedModuleReceiptSHA256': digest(stamp),
        'moduleOutputs': receipt['outputs'], 'compilerArguments': command,
        'assetsSHA256': {path.name: digest(path) for path in sorted(output.glob('DABIN__GUIDE__*.png'))},
        'nativeRenderManifestSHA256': digest(output / 'guide-native-renders.json'),
        'scope': 'Real production views linked to the verified Store QA module; not a distribution-signed app screenshot certification.'
    }
    (output / 'guide-native-source-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print('Source-verified guide assets:', output)


if __name__ == '__main__':
    main()
