#!/usr/bin/env python3
"""Shared, deterministic inventory for local builds, QA, and the Xcode project."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = "arm64-apple-macosx14.0"
RESOURCE_TYPES = {
    "Resources/AppIcon.icns": "image.icns",
    "Resources/PrivacyInfo.xcprivacy": "text.xml",
    "Resources/PrivacyPolicy.md": "text",
    "Resources/robot.svg": "image.svg",
}

def sources(include_main=True):
    result = sorted(ROOT.glob("Sources/DaBin/*.swift"))
    return result if include_main else [p for p in result if p.name != "DaBinMain.swift"]

def resources():
    return [ROOT / name for name in sorted(RESOURCE_TYPES)]

def source_group(path):
    name = path.stem
    if name in {"DaBinMain", "AppDelegate", "AppComposition", "AppEnvironment", "AppDependencies", "StatusBarController"} or "Composition" in name or name.startswith("Application"):
        return "Application"
    if name in {"Domain", "AppState", "AutoCaptureSettings", "HourlyCaptureFeed", "DayExport"}:
        return "State and Domain"
    if name in {"CaptureStore", "CaptureRepository", "CaptureRemoval", "DailyArchive", "OriginalFileStorage"}:
        return "Storage"
    if name in {"InputService", "PreviewService", "ContentIndexService", "ReminderService", "ReminderLifecycle", "PreviewRequest",
                "AutoCaptureService", "AutoCaptureFingerprint", "CaptureClipboard", "ScreenshotFolderMonitor"}:
        return "Services"
    if name in {"CornerController", "RobotView", "WindowDragHandle", "DailyCaptureView",
                "AutoCaptureRobotPresenter", "AutoCaptureRobotCelebration"}:
        return "Desktop"
    return "Interface"

def hashes(paths):
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(paths))}

def fingerprint(values):
    return hashlib.sha256(json.dumps(values, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def build_inventory():
    paths = sources() + resources() + [ROOT / "Resources/Info.plist", ROOT / "Resources/DaBin.entitlements"]
    paths += sorted(ROOT.glob("scripts/*.py")) + sorted(ROOT.glob("scripts/*.sh"))
    paths += sorted(ROOT.glob("UpdateTools/*.swift"))
    return hashes(paths)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--without-main", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    paths = sources(not args.without_main)
    if args.json:
        print(json.dumps(hashes(paths), indent=2, sort_keys=True))
    else:
        for path in paths:
            print(path.relative_to(ROOT))

if __name__ == "__main__":
    main()
