#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build/tests build/ModuleCache build/qa/screenshots
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(python3 scripts/project_inventory.py --without-main)
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 -warnings-as-errors -D DABIN_DIRECT_UPDATES \
  -module-cache-path build/ModuleCache -parse-as-library \
  "${sources[@]}" Tests/NativeRenderTests.swift -o build/tests/NativeRenderTests
cp -X Resources/robot.svg build/tests/robot.svg
build/tests/NativeRenderTests build/qa/screenshots "$@"
