#!/bin/bash
# Separate integration suite. Default execution has no network access.
# --link-smoke explicitly adds one request to https://www.apple.com/.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build/tests build/ModuleCache
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(python3 scripts/project_inventory.py --without-main)
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 -warnings-as-errors \
  -module-cache-path build/ModuleCache -parse-as-library \
  "${sources[@]}" Tests/MediaIntegrationTests.swift -o build/tests/MediaIntegrationTests
build/tests/MediaIntegrationTests "$@"
