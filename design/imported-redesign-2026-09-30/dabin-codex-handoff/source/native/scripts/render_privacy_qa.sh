#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
output="$project_root/build/qa/privacy"
mkdir -p "$output" build/ModuleCache
stage="$(mktemp -d "${TMPDIR:-/tmp}/dabin-privacy-render.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/DaBin Privacy Render.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -X Resources/PrivacyPolicy.md "$app/Contents/Resources/PrivacyPolicy.md"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dabin.qa.privacy-render</string>
<key>CFBundleExecutable</key><string>PrivacyRenderTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 \
  -warnings-as-errors -module-cache-path build/ModuleCache -parse-as-library \
  Sources/DaBin/ThemeSettings.swift Sources/DaBin/PrivacyInformation.swift Tests/PrivacyRenderTests.swift \
  -o "$app/Contents/MacOS/PrivacyRenderTests"
"$app/Contents/MacOS/PrivacyRenderTests" "$output" > "$output/privacy-render.log" 2>&1
cat "$output/privacy-render.log"
