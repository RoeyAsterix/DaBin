"""Read-only release input checks shared by the local review-asset builders."""
import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def add_release_arguments(parser, *, module=True):
    parser.add_argument('--version', help='Expected version; defaults to the selected native Info.plist')
    parser.add_argument('--build', help='Expected build; defaults to the selected native Info.plist')
    parser.add_argument('--native-root', type=Path, default=ROOT / 'native',
                        help='Current native source or an explicitly frozen copy inside native/')
    if module:
        parser.add_argument('--module-cache', type=Path,
                            help='Exact verified Release Store QA cache; otherwise choose a matching receipt')


def read_release(args, *, module=True):
    native = args.native_root.resolve()
    if not native.is_relative_to(ROOT / 'native'):
        raise SystemExit('Native inputs must be the project native root or its explicitly frozen descendant.')
    spec = importlib.util.spec_from_file_location('review_asset_inventory', native / 'scripts/project_inventory.py')
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    info_path = native / 'Resources/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if ((args.version is not None and args.version != version)
            or (args.build is not None and args.build != build)):
        raise SystemExit(f'Expected {args.version or version} ({args.build or build}); selected native source is {version} ({build}).')
    result = {'native': native, 'inventory': inventory, 'version': version, 'build': build,
              'info': info, 'infoSHA256': digest(info_path),
              'sources': inventory.hashes(inventory.sources(False)),
              'resources': inventory.hashes(inventory.resources())}
    if not module:
        return result
    stamps = ([args.module_cache.resolve() / 'module-ready.json'] if args.module_cache
              else (native / 'build/qa-cache').glob('*/module-ready.json'))
    matches = []
    for stamp in stamps:
        try:
            receipt = json.loads(stamp.read_text())
            inputs = receipt['inputs']
            if (inputs['sources'] != result['sources'] or inputs['configuration'] != 'Release'
                    or inputs.get('distribution') != 'app-store' or inputs.get('compileDefinitions', []) != []
                    or inputs['target'] != inventory.TARGET
                    or set(receipt['outputs']) != {'DaBinTestCore.swiftmodule', 'libDaBinTestCore.dylib'}):
                continue
            if all(digest(stamp.parent / name) == sha for name, sha in receipt['outputs'].items()):
                matches.append((stamp.stat().st_mtime, stamp, receipt))
        except (OSError, KeyError, ValueError):
            continue
    if not matches:
        raise SystemExit('No source-matched, hash-verified Release Store QA module. Finish coordinated QA first.')
    _, stamp, receipt = max(matches, key=lambda item: item[0])
    result.update({'moduleStamp': stamp, 'moduleReceipt': receipt, 'moduleCache': stamp.parent})
    return result


def verify_unchanged(release):
    inventory, native = release['inventory'], release['native']
    if (inventory.hashes(inventory.sources(False)) != release['sources']
            or inventory.hashes(inventory.resources()) != release['resources']
            or digest(native / 'Resources/Info.plist') != release['infoSHA256']):
        raise SystemExit('Native inputs changed during asset preparation; reject this output.')


def verify_asset_manifest(manifest, release):
    if ((manifest.get('version'), manifest.get('build')) != (release['version'], release['build'])
            or manifest.get('distribution') != 'app-store'
            or manifest.get('sourceSHA256') != release['sources']
            or manifest.get('resourceSHA256') != release['resources']):
        raise SystemExit('Asset manifest does not match the selected Store release source and resources.')
