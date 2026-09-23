#!/usr/bin/env python3
"""Build a standalone local Apple Silicon app; no account or upload operations."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from project_inventory import ROOT, TARGET, sources, resources, build_inventory, fingerprint

def run(arguments, **kwargs):
    return subprocess.run([str(item) for item in arguments], check=True, **kwargs)

def output(arguments):
    return subprocess.check_output(arguments, text=True).strip()

def copy_permissions(source, destination):
    shutil.copyfile(source, destination)
    shutil.copymode(source, destination)

def copy_tree_without_metadata(source, destination):
    """Copy owned bundle bytes/modes, without Finder metadata or dereferencing links."""
    source, destination = Path(source), Path(destination)
    if source.is_symlink():
        raise ValueError(f"Refusing to copy symlink: {source}")
    destination.mkdir()
    for entry in sorted(source.iterdir()):
        if entry.is_symlink():
            raise ValueError(f"Refusing to copy symlink: {entry}")
        target = destination / entry.name
        if entry.is_dir():
            copy_tree_without_metadata(entry, target)
        elif entry.is_file():
            copy_permissions(entry, target)
        else:
            raise ValueError(f"Refusing unsupported bundle entry: {entry}")
    shutil.copymode(source, destination)


def build_update_helper(app, sdk, identity, version, build_number):
    helper = app / "Contents/Helpers/DaBin Update.app"
    executable = helper / "Contents/MacOS/DaBinUpdate"
    resources = helper / "Contents/Resources"
    executable.parent.mkdir(parents=True)
    resources.mkdir()
    run(["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET, "-sdk", sdk,
         "-warnings-as-errors", "-O", "-whole-module-optimization", "-parse-as-library",
         ROOT / "UpdateTools/DaBinUpdater.swift", "-o", executable])
    helper_info = {
        "CFBundleIdentifier": "com.dabin.mac.updater.local",
        "CFBundleName": "DaBin Update",
        "CFBundleDisplayName": "DaBin Update",
        "CFBundleExecutable": "DaBinUpdate",
        "CFBundleIconFile": "AppIcon",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": build_number,
        "CFBundleShortVersionString": version,
        "NSPrincipalClass": "NSApplication",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "© 2026 DaBin",
    }
    (helper / "Contents/Info.plist").write_bytes(plistlib.dumps(helper_info))
    copy_permissions(ROOT / "Resources/AppIcon.icns", resources / "AppIcon.icns")
    arguments = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        arguments += ["--options", "runtime", "--timestamp"]
    run([*arguments, helper])
    run(["codesign", "--verify", "--deep", "--strict", helper])
    return helper


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["Release", "Debug"], default="Release")
    parser.add_argument("--debug", action="store_true", help="Shortcut for --configuration Debug")
    args = parser.parse_args()
    configuration = "Debug" if args.debug else args.configuration
    os.chdir(ROOT)
    inventory = build_inventory()
    source_hash = fingerprint(inventory)
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    (build / "ModuleCache").mkdir(exist_ok=True)
    sdk = output(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    compiler_version = output(["xcrun", "swiftc", "--version"])
    flags = ["-O", "-whole-module-optimization"] if configuration == "Release" else ["-Onone", "-D", "DEBUG"]
    with tempfile.TemporaryDirectory(prefix="dabin-build-") as temporary:
        stage = Path(temporary)
        app = stage / "DaBin.app"
        executable = app / "Contents/MacOS/DaBin"
        executable.parent.mkdir(parents=True)
        resource_directory = app / "Contents/Resources"
        resource_directory.mkdir()
        run(["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET,
             "-module-cache-path", build / "ModuleCache", "-sdk", sdk,
             "-warnings-as-errors", "-g", "-D", "DABIN_DIRECT_UPDATES", *flags,
             "-parse-as-library", *sources(), "-o", executable])
        symbols = stage / "DaBin.app.dSYM"
        incidental_symbols = executable.with_suffix(".dSYM")
        if incidental_symbols.exists():
            incidental_symbols.rename(symbols)
        else:
            run(["xcrun", "dsymutil", executable, "-o", symbols])
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        info["DaBinBuildConfiguration"] = configuration
        info["DaBinSourceFingerprint"] = source_hash
        info["DaBinDistributionChannel"] = "github"
        info["DaBinUpdateManifestURL"] = "https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json"
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        for resource in resources():
            copy_permissions(resource, resource_directory / resource.name)
        identity = os.environ.get("DABIN_SIGNING_IDENTITY", "-")
        build_update_helper(app, sdk, identity, info["CFBundleShortVersionString"], info["CFBundleVersion"])
        sign_arguments = ["codesign", "--force", "--sign", identity]
        if identity != "-":
            sign_arguments += ["--options", "runtime", "--timestamp"]
        run([*sign_arguments, "--entitlements", ROOT / "Resources/DaBin.entitlements", app])
        run(["codesign", "--verify", "--deep", "--strict", app])
        if output(["lipo", "-archs", str(executable)]) != "arm64":
            raise SystemExit("Refusing to deliver a non-ARM64 local build")
        if inventory != build_inventory():
            raise SystemExit("Source changed during the build. Previous output preserved; rebuild after edits finish.")
        for name in ("DaBin.app", "DaBin.app.dSYM"):
            destination = build / name
            if destination.is_symlink():
                raise SystemExit(f"Refusing to replace symlink: {destination}")
            if destination.exists():
                if name == "DaBin.app" and plistlib.loads((destination / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier") != "com.dabin.mac":
                    raise SystemExit("Refusing to replace an unrelated application")
                shutil.rmtree(destination)
            copy_tree_without_metadata(stage / name, destination)
        # Finder can reattach metadata in synced Documents folders. Verify the
        # exact copied bytes outside that directory, without transferring xattrs.
        verified = stage / "Verified.app"
        copy_tree_without_metadata(build / "DaBin.app", verified)
        run(["codesign", "--verify", "--deep", "--strict", verified])
        receipt = {
            "schemaVersion": 1, "builtAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "configuration": configuration, "target": TARGET, "swiftVersion": compiler_version,
            "sdkVersion": output(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            "version": info["CFBundleShortVersionString"], "buildNumber": info["CFBundleVersion"],
            "sourceFingerprint": source_hash, "inputs": inventory,
            "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
            "strictSignatureVerifiedOnCleanCopy": True,
            "distributionChannel": "github",
            "embeddedUpdateHelper": True,
            "appStoreApproved": False, "distributionValidated": False,
        }
        (build / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(f"Built {configuration} ARM64 app: {build / 'DaBin.app'}")
    print(f"Debug symbols remain outside the app: {build / 'DaBin.app.dSYM'}")
    print("Local signing is separate from App Store distribution validation.")

if __name__ == "__main__":
    main()
