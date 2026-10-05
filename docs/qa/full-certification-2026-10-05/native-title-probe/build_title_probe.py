#!/usr/bin/env python3
"""Compile-only, separate visible native probe; never launches a GUI executable."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, plistlib, shlex, shutil, subprocess, time

p = argparse.ArgumentParser()
p.add_argument('--module-dir', type=Path, required=True)
p.add_argument('--native-root', type=Path, default=Path(__file__).resolve().parents[4] / 'native')
a = p.parse_args()
base = Path(__file__).resolve().parent
native, module = a.native_root.resolve(), a.module_dir.resolve()
helper = base.parent / 'extra-render-qa/run_extra_renders.py'
spec = importlib.util.spec_from_file_location('extra_render_validation', helper)
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)
verified = validation.validate_module(native, module)
source = base / 'DaBinTitleRenderProbe.swift'
app = base / 'apps/DaBinTitleRenderProbe.app'
contents = app / 'Contents'
macos, resources = contents / 'MacOS', contents / 'Resources'
macos.mkdir(parents=True, exist_ok=True); resources.mkdir(exist_ok=True)
for name in validation.PRODUCTION_RESOURCES:
    shutil.copyfile(native / 'Resources' / name, resources / name)
info = plistlib.loads((native / 'Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='DaBinTitleRenderProbe', CFBundleIdentifier='com.dabin.mac.qa.native-title-probe',
            CFBundleName='DaBinTitleRenderProbe', CFBundleDisplayName='DaBin native title probe', LSUIElement=False)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
output = base / 'output'; output.mkdir(exist_ok=True)
executable = macos / 'DaBinTitleRenderProbe'
command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', validation.TARGET,
           '-module-cache-path', str(base / 'ModuleCache'), '-warnings-as-errors', '-parse-as-library',
           '-O', '-whole-module-optimization', '-I', str(module), '-L', str(module), '-lDaBinTestCore',
           '-Xlinker', '-rpath', '-Xlinker', str(module), str(source), '-o', str(executable)]
report = {'scope': 'Compile-only separate app; unmodified production Board/native editable title and optional real extended video surface',
          'runtimeLaunchedByBuild': False, 'moduleDirectory': str(module), 'verifiedModule': verified,
          'source': str(source), 'sourceSHA256': validation.sha(source), 'compileCommand': command,
          'compileCommandShell': shlex.join(command), 'appBundle': str(app), 'processName': 'DaBinTitleRenderProbe',
          'output': str(output), 'recommendedRuntimeCommand': [str(executable), str(output)],
          'defaultRuntime': 'Visible physical non-fullscreen 380×680 Board content, 100% zoom/light, same synthetic task and native title field',
          'optionalRuntime': 'Probe menu > Open synthetic video (Cmd+2): silent local 320×180 8s H.264 MOV in actual production extended canvas; Cmd+1 returns to title',
          'runtimeSafety': 'Private archive and preferences; Auto Capture/links off; fake clipboard and notification clients; App Store inert updater; blocked Finder and export operations',
          'cleanup': 'Close native title window, use production Board Close, or Cmd+Q; 180s auto-close. All own windows/services/private archive/preferences cleaned; output artifacts retained. Root must terminate only this PID if wedged.',
          'expectedArtifacts': ['launch-ready.json', 'cache-display-visible-window@2x.png', 'cleanup.json'],
          'optionalArtifacts': ['video-ready.json'],
          'artifactsNotCapturedByBuild': 'Physical window screenshot and real AVKit transport activation are root-owned CUA observation, not replaced by cached pixels',
          'resourceInputs': {str(f.relative_to(native)): validation.sha(f) for f in sorted((native / 'Resources').rglob('*')) if f.is_file()},
          'bundleResourceSHA256': {n: validation.sha(resources / n) for n in validation.PRODUCTION_RESOURCES},
          'bundleInfoSHA256': validation.sha(contents / 'Info.plist')}
manifest = base / 'probe-manifest.json'
validation.write_json(manifest, report)
report['compile'] = validation.owned_operation(command, native, base / 'compile.log', 180)
report['status'] = report['compile']['status']
if executable.is_file(): report['executableSHA256'] = validation.sha(executable)
report['productionSourceChangedDuringCompile'] = validation.current_sources(native) != verified['productionSources']
if report['productionSourceChangedDuringCompile']: report['status'] = 'invalidated_by_source_changes'
report['finishedAtUTC'] = validation.now()
validation.write_json(manifest, report)
print('MANIFEST', manifest, report['status'], flush=True)
raise SystemExit(0 if report['status'] == 'passed' else 1)
