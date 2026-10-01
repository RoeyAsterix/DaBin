#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build/tests build/ModuleCache build/qa/walkthrough
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(python3 scripts/project_inventory.py --without-main)
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 -warnings-as-errors -D DABIN_DIRECT_UPDATES \
  -module-cache-path build/ModuleCache -parse-as-library \
  "${sources[@]}" Tests/WalkthroughRenderTests.swift -o build/tests/WalkthroughRenderTests
cp -X Resources/robot.svg build/tests/robot.svg
build/tests/WalkthroughRenderTests build/qa/walkthrough ../design/walkthrough/assets/Launch-plan.txt
