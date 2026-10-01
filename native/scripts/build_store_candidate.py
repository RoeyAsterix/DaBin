#!/usr/bin/env python3
"""Build an isolated unsigned Store Release compile; never sign, install or upload."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

from project_inventory import ROOT, build_inventory, fingerprint, hashes


def validate_output_directory(destination):
    destination = destination.expanduser().absolute()
    if ".." in destination.parts:
        raise ValueError("Candidate output may not contain parent-directory traversal")
    allowed = (ROOT / "build", ROOT.parent / "build")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Candidate directory already exists; choose a new owned output directory")
    if not any(destination.is_relative_to(base) and destination != base for base in allowed):
        raise ValueError("Candidate output must be a new subdirectory of DaBin/build or DaBin/native/build")
    for path in (destination, *destination.parents):
        if path.is_symlink():
            raise ValueError(f"Candidate output has a symbolic-link ancestor: {path}")
    return destination


def candidate_info(info, source_fingerprint):
    result = dict(info)
    result["DaBinBuildConfiguration"] = "Release"
    result["DaBinSourceFingerprint"] = source_fingerprint
    result.pop("DaBinUpdateManifestURL", None)
    result.pop("DaBinDistributionChannel", None)
    return result


def input_snapshot():
    result = build_inventory()
    result.update(hashes([
        ROOT / "Config/AppStoreSigning.json",
        ROOT / "DaBin.xcodeproj/project.pbxproj",
        ROOT / "DaBin.xcodeproj/xcshareddata/xcschemes/DaBin.xcscheme",
    ]))
    return result


def build_arguments(destination, info):
    return [
        "xcrun", "xcodebuild", "-project", str(ROOT / "DaBin.xcodeproj"),
        "-scheme", "DaBin", "-configuration", "Release",
        "-destination", "generic/platform=macOS",
        "-derivedDataPath", str(destination / "derived-data"),
        "-disableAutomaticPackageResolution", "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "ARCHS=arm64",
        "ONLY_ACTIVE_ARCH=NO", "SWIFT_ACTIVE_COMPILATION_CONDITIONS=",
        "INFOPLIST_FILE=" + str(info), "build",
    ]


def command_output(arguments):
    result = subprocess.run(arguments, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    return {"exitCode": result.returncode, "output": result.stdout.strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parser.add_argument("--output-directory", type=Path,
                        default=ROOT / "build" / ("store-unsigned-" + stamp))
    args = parser.parse_args()
    try:
        destination = validate_output_directory(args.output_directory)
    except ValueError as error:
        parser.error(str(error))

    inputs = input_snapshot()
    source_fingerprint = fingerprint(build_inventory())
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    destination.mkdir(parents=True)
    candidate_plist = destination / "Store-Info.plist"
    candidate_plist.write_bytes(plistlib.dumps(candidate_info(info, source_fingerprint)))
    arguments = build_arguments(destination, candidate_plist)
    build_log = destination / "xcodebuild-release.log"
    with build_log.open("w") as stream:
        result = subprocess.run(arguments, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                check=False)

    app = destination / "derived-data/Build/Products/Release/DaBin.app"
    executable = app / "Contents/MacOS/DaBin"
    unchanged = inputs == input_snapshot()
    preflight_log = destination / "unsigned-packaging-preflight.log"
    preflight_exit = None
    if result.returncode == 0 and unchanged:
        with preflight_log.open("w") as stream:
            preflight = subprocess.run(
                [sys.executable, str(ROOT / "scripts/app_store_preflight.py"),
                 "--unsigned-app", str(app)], cwd=ROOT,
                stdout=stream, stderr=subprocess.STDOUT, check=False,
            )
        preflight_exit = preflight.returncode
        unchanged = inputs == input_snapshot()

    receipt = {
        "schemaVersion": 1,
        "builtAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "configuration": "Release", "architecture": "arm64", "minimumMacOS": "14.0",
        "version": info["CFBundleShortVersionString"], "buildNumber": info["CFBundleVersion"],
        "sourceFingerprint": source_fingerprint, "inputs": inputs,
        "inputsUnchanged": unchanged, "xcodebuildExitCode": result.returncode,
        "packagingPreflightExitCode": preflight_exit, "command": arguments,
        "xcode": command_output(["xcrun", "xcodebuild", "-version"]),
        "sdk": command_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
        "swift": command_output(["xcrun", "swiftc", "--version"]),
        "app": str(app), "buildLog": str(build_log), "preflightLog": str(preflight_log),
        "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest() if executable.is_file() else None,
        "distributionChannel": "mac-app-store-unsigned-compile-only",
        "signed": False, "sandboxRuntimeVerified": False, "archiveCreated": False,
        "uploaded": False, "appStoreApproved": False,
    }
    (destination / "store-candidate-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    if result.returncode or preflight_exit != 0 or not unchanged:
        print(f"Unsigned Store compile failed or is not current. Inspect: {destination}")
        return 1
    print(f"Unsigned Store Release compiled and packaging-checked: {app}")
    print("This is not a distribution archive. Signing, sandbox runtime QA and Apple validation/review remain pending.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
