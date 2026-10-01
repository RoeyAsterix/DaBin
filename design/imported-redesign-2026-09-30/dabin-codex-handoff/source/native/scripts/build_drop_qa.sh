#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
staging_root="$(mktemp -d /private/tmp/dabin-drop-qa.XXXXXX)"
trap 'rm -rf "$staging_root"' EXIT
app_path="$staging_root/DaBin Drop QA.app"
mkdir -p build/ModuleCache "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(python3 scripts/project_inventory.py --without-main)
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 \
  -module-cache-path build/ModuleCache -warnings-as-errors -D DABIN_DIRECT_UPDATES -parse-as-library \
  "${sources[@]}" Tests/NativeDropQAMain.swift \
  -o "$app_path/Contents/MacOS/DaBinDropQA"
cp -X Resources/robot.svg "$app_path/Contents/Resources/robot.svg"
python3 - "$app_path" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1])
info = {
    'CFBundleIdentifier': 'com.dabin.mac.qa.drop',
    'CFBundleName': 'DaBin Drop QA',
    'CFBundleExecutable': 'DaBinDropQA',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'NSPrincipalClass': 'NSApplication',
    'LSMinimumSystemVersion': '14.0',
    'LSUIElement': False,
}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
python3 - "$app_path" <<'PY'
from pathlib import Path
import plistlib, shutil, sys
source = Path(sys.argv[1])
destination = Path('/private/tmp/DaBin Drop QA.app')
if destination.exists():
    info = plistlib.loads((destination/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.dabin.mac.qa.drop':
        raise SystemExit('Refusing to replace an unrelated app')
    shutil.rmtree(destination)
shutil.copytree(source, destination)
print(destination)
print('Summary: /private/tmp/DaBinDropQA-results.json')
PY
codesign --verify --deep --strict '/private/tmp/DaBin Drop QA.app'
