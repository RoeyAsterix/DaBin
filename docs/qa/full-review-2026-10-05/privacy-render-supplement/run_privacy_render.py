#!/usr/bin/env python3
"""Link unchanged PrivacyRenderTests to an exact verified Store QA module."""
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RENDER_FILES = ['privacy-policy-light-top.png', 'privacy-policy-light-bottom.png',
                'privacy-policy-dark-top.png', 'privacy-policy-dark-bottom.png']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module_name(runner):
    for node in ast.parse(runner.read_text()).body:
        if (isinstance(node, ast.Assign) and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'MODULE'
                and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)):
            name = node.value.value
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                return name
    raise SystemExit('Selected run_qa.py must define one literal valid Swift MODULE name.')


def input_snapshot(native, inventory, test):
    return {'sources': inventory.hashes(inventory.sources(False)),
            'resources': inventory.hashes(inventory.resources()),
            'infoSHA256': digest(native / 'Resources/Info.plist'),
            'runnerSHA256': digest(native / 'scripts/run_qa.py'),
            'inventorySHA256': digest(native / 'scripts/project_inventory.py'),
            'testSHA256': digest(test)}


def read_inputs(args):
    native = args.native_root.resolve()
    if not native.is_relative_to(ROOT / 'native'):
        raise SystemExit('Select the project native source or its explicit frozen descendant.')
    runner = native / 'scripts/run_qa.py'
    name = module_name(runner)
    spec = importlib.util.spec_from_file_location('privacy_render_inventory', native / 'scripts/project_inventory.py')
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    test = native / 'Tests/PrivacyRenderTests.swift'
    snapshot = input_snapshot(native, inventory, test)
    info = plistlib.loads((native / 'Resources/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if (version, build) != (args.version, args.build):
        raise SystemExit(f'Source is {version} ({build}), expected {args.version} ({args.build}).')
    cache = args.module_cache.resolve()
    stamp = cache / 'module-ready.json'
    receipt = json.loads(stamp.read_text())
    inputs = receipt['inputs']
    expected_outputs = {name + '.swiftmodule', 'lib' + name + '.dylib'}
    if (inputs.get('sources') != snapshot['sources'] or inputs.get('configuration') != 'Release'
            or inputs.get('distribution') != 'app-store' or inputs.get('compileDefinitions', []) != []
            or inputs.get('target') != inventory.TARGET
            or inputs.get('runner') != snapshot['runnerSHA256']
            or inputs.get('inventory') != snapshot['inventorySHA256']
            or set(receipt.get('outputs', {})) != expected_outputs):
        raise SystemExit('Exact source/runner/inventory-matched app-store Release QA module required.')
    for filename, expected in receipt['outputs'].items():
        if digest(cache / filename) != expected:
            raise SystemExit(f'QA module output changed: {filename}')
    return {'native': native, 'inventory': inventory, 'test': test, 'snapshot': snapshot,
            'moduleName': name, 'cache': cache, 'stamp': stamp, 'receipt': receipt,
            'version': version, 'build': build, 'target': inventory.TARGET,
            'stampSHA256': digest(stamp)}


def unchanged(inputs):
    try:
        return (input_snapshot(inputs['native'], inputs['inventory'], inputs['test']) == inputs['snapshot']
                and digest(inputs['stamp']) == inputs['stampSHA256']
                and all(digest(inputs['cache'] / name) == sha
                        for name, sha in inputs['receipt']['outputs'].items()))
    except (OSError, ValueError):
        return False


def run_logged(command, cwd, log, timeout):
    started = time.monotonic()
    try:
        result = subprocess.run([str(value) for value in command], cwd=cwd,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=timeout, check=False)
        output, status, code = result.stdout, 'passed' if result.returncode == 0 else 'failed', result.returncode
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ''
        if isinstance(output, bytes):
            output = output.decode(errors='replace')
        status, code = 'timeout', None
    log.write_text(output)
    return {'status': status, 'exitCode': code, 'seconds': round(time.monotonic() - started, 3),
            'log': str(log), 'command': [str(value) for value in command]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-root', type=Path, default=ROOT / 'native')
    parser.add_argument('--module-cache', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument('--check-inputs', action='store_true', help='Verify receipts only; no compile or GUI')
    operation.add_argument('--run', action='store_true', help='Compile and run only after root releases final coordinated GUI stage')
    parser.add_argument('--output-root', type=Path, default=HERE / 'runs')
    args = parser.parse_args()
    inputs = read_inputs(args)
    identity = {'version': inputs['version'], 'build': inputs['build'], 'distribution': 'app-store',
                'configuration': 'Release', 'moduleName': inputs['moduleName'],
                'target': inputs['target'], 'moduleReceipt': str(inputs['stamp']),
                'moduleReceiptSHA256': inputs['stampSHA256'], 'moduleOutputs': inputs['receipt']['outputs'],
                'testSource': str(inputs['test']), **inputs['snapshot']}
    if args.check_inputs:
        print(json.dumps({'status': 'INPUTS_VERIFIED_NO_COMPILE_OR_RUN', 'inputs': identity}, indent=2))
        return 0
    # Toolchain identity belongs to the selected receipt, just as in run_qa.py.
    compiler = subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True, stderr=subprocess.STDOUT).strip()
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True, stderr=subprocess.STDOUT).strip()
    if (compiler, sdk) != (inputs['receipt']['inputs']['compiler'], inputs['receipt']['inputs']['sdk']):
        raise SystemExit('Current compiler/SDK differs from the exact final QA module toolchain.')
    output_root = args.output_root.resolve()
    if not output_root.is_relative_to(ROOT / 'docs/qa/full-review-2026-10-05'):
        raise SystemExit('Supplemental evidence must stay within this full-review package.')
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8]
    output = output_root / run_id
    output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'RUNNING', 'runID': run_id, 'inputs': identity,
              'runnerSHA256': digest(Path(__file__)), 'productionModuleRecompiled': False,
              'originalTestModified': False, 'fixturePublicLinks': 'Absent by design, as required by the original test',
              'fixturePrivacy': 'Current local policy and production policy view only; unique owned bundle/non-key offscreen windows, no personal archive, clipboard, network, permissions, notifications or global input.',
              'visualReview': 'Pending all four original-resolution PNG inspections.'}
    try:
        with tempfile.TemporaryDirectory(prefix='DaBinPrivacyRender-', dir='/private/tmp') as temporary:
            scratch = Path(temporary)
            bundle = scratch / ('PrivacyRender-' + run_id + '.app')
            contents = bundle / 'Contents'
            macos, resources, frameworks = contents / 'MacOS', contents / 'Resources', contents / 'Frameworks'
            for folder in (macos, resources, frameworks):
                folder.mkdir(parents=True)
            wrapper = scratch / 'PrivacyRenderTests.swift'
            wrapper.write_text('@testable import ' + inputs['moduleName'] + '\n' + inputs['test'].read_text())
            policy = inputs['native'] / 'Resources/PrivacyPolicy.md'
            shutil.copy2(policy, resources / 'PrivacyPolicy.md')
            library_name = 'lib' + inputs['moduleName'] + '.dylib'
            shutil.copy2(inputs['cache'] / library_name, frameworks / library_name)
            if digest(frameworks / library_name) != inputs['receipt']['outputs'][library_name]:
                raise RuntimeError('Temporary bundle library does not match the exact cached module.')
            executable = macos / 'PrivacyRenderTests'
            info = {'CFBundleIdentifier': 'com.dabin.qa.privacy.' + uuid.uuid4().hex,
                    'CFBundleName': 'DaBin Privacy Render QA', 'CFBundleExecutable': executable.name,
                    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': inputs['version'],
                    'CFBundleVersion': inputs['build'], 'LSMinimumSystemVersion': '14.0',
                    'LSUIElement': True, 'NSHighResolutionCapable': True}
            plistlib.dump(info, (contents / 'Info.plist').open('wb'))
            runtime_renders = scratch / 'renders'
            runtime_renders.mkdir()
            command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', inputs['target'],
                       '-module-cache-path', scratch / 'ModuleCache', '-warnings-as-errors',
                       '-parse-as-library', '-O', '-whole-module-optimization',
                       '-I', inputs['cache'], '-L', inputs['cache'], '-l' + inputs['moduleName'],
                       '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', wrapper, '-o', executable]
            report['compile'] = run_logged(command, scratch, output / 'compile.log', 180)
            report['wrapperSHA256'] = digest(wrapper)
            report['fixtureInfo'] = info
            report['fixtureInfoSHA256'] = digest(contents / 'Info.plist')
            report['bundledPolicySHA256'] = digest(resources / 'PrivacyPolicy.md')
            report['policyUpdated'] = next((line for line in policy.read_text().splitlines() if line.startswith('Updated ')), None)
            if report['compile']['status'] != 'passed':
                report['status'] = 'COMPILE_FAILED'
            elif not unchanged(inputs):
                report['status'] = 'INVALIDATED_BY_INPUT_CHANGES_BEFORE_RUN'
            else:
                report['executableSHA256'] = digest(executable)
                report['execute'] = run_logged([executable, runtime_renders], scratch, output / 'runtime.log', 90)
                shutil.copytree(runtime_renders, output / 'renders')
                report['status'] = 'PASS' if report['execute']['status'] == 'passed' else 'RUNTIME_FAILED'
                if report['status'] == 'PASS':
                    from PIL import Image
                    artifacts = []
                    for filename in RENDER_FILES:
                        path = output / 'renders' / filename
                        with Image.open(path) as rendered:
                            if rendered.size != (350, 440):
                                raise RuntimeError('Unexpected privacy render dimensions: ' + filename)
                            rendered.verify()
                        artifacts.append({'file': 'renders/' + filename, 'sha256': digest(path), 'width': 350, 'height': 440})
                    report['renders'] = artifacts
                    report['nativeRenderManifestSHA256'] = digest(output / 'renders/privacy-renders.json')
    except Exception as error:
        report['status'] = 'FAILED'
        report['error'] = str(error)
    report['sourceAndModuleUnchanged'] = unchanged(inputs)
    if not report['sourceAndModuleUnchanged']:
        report['status'] = 'INVALIDATED_BY_INPUT_CHANGES'
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'report': str(output / 'report.json'),
                      'visualReview': report['visualReview']}, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
