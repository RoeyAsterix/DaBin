#!/usr/bin/env python3
"""Offline release checks. Passing does not replace Xcode/App Store validation."""
import argparse
import ipaddress
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import urlsplit
from project_inventory import sources, resources

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    print(("PASS: " if condition else "BLOCKED: ") + message)
    if not condition:
        errors.append(message)


def read_plist(path):
    try:
        return plistlib.loads(path.read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        check(False, f"Readable property list at {path}: {error}")
        return {}


def public_https(value):
    try:
        if not isinstance(value, str) or any(character.isspace() for character in value):
            return False
        parts = urlsplit(value)
        _ = parts.port  # Reject malformed port syntax without making a request.
        host = (parts.hostname or "").lower().rstrip(".")
        if parts.scheme != "https" or not host or parts.username or parts.password:
            return False
        if "." not in host or host.endswith((".localhost", ".local", ".invalid", ".test", ".example")):
            return False
        if any(host == suffix or host.endswith("." + suffix) for suffix in ("example.com", "example.org", "example.net")):
            return False
        try:
            if not ipaddress.ip_address(host).is_global:
                return False
        except ValueError:
            if not all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
                       for label in host.split(".")):
                return False
        return True
    except ValueError:
        return False


def command(arguments):
    try:
        return subprocess.run(arguments, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, check=False)
    except OSError as error:
        return subprocess.CompletedProcess(arguments, 1, str(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true", help="Check source packaging only; does not report release readiness")
    parser.add_argument("--app", type=Path, help="Also inspect a distribution-signed app bundle; an ad-hoc app must fail")
    args = parser.parse_args()
    if args.static_only and args.app:
        parser.error("--static-only and --app cannot be combined")
    errors.clear()
    info = read_plist(ROOT / "Resources/Info.plist")
    entitlements = read_plist(ROOT / "Resources/DaBin.entitlements")
    manifest = read_plist(ROOT / "Resources/PrivacyInfo.xcprivacy")
    check(bool(info.get("CFBundleIdentifier")), "Bundle identifier is configured (ownership must be verified in the developer account)")
    check(info.get("LSApplicationCategoryType") == "public.app-category.productivity", "Productivity category is configured")
    check(bool(info.get("NSHumanReadableCopyright")), "Copyright is present (publisher must confirm ownership)")
    check(bool(re.fullmatch(r"\d+(?:\.\d+){0,2}", info.get("CFBundleShortVersionString", ""))), "Marketing version has a numeric release format")
    check(bool(re.fullmatch(r"\d+(?:\.\d+){0,2}", info.get("CFBundleVersion", ""))), "Build number has a numeric release format")
    check(entitlements.get("com.apple.security.app-sandbox") is True, "App Sandbox is enabled")
    check(not entitlements.get("com.apple.security.get-task-allow"), "Source entitlement file does not allow debugger attachment")
    check(manifest.get("NSPrivacyTracking") is False, "Bundled manifest declares no tracking")
    check(isinstance(manifest.get("NSPrivacyCollectedDataTypes"), list), "Manifest contains the collected-data declaration")
    check((ROOT / "Resources/PrivacyPolicy.md").is_file(), "Readable in-app privacy policy resource exists")
    project = ROOT / "DaBin.xcodeproj/project.pbxproj"
    project_text = project.read_text() if project.is_file() else ""
    for name in ("PrivacyInfo.xcprivacy", "PrivacyPolicy.md", "PrivacyInformation.swift"):
        check(name in project_text, f"Xcode project includes {name}")

    update_source = (ROOT / "Sources/DaBin/SoftwareUpdateService.swift").read_text()
    build_source = (ROOT / "scripts/build_app.py").read_text()
    check("#if DABIN_DIRECT_UPDATES" in update_source and "DABIN_DIRECT_UPDATES" not in project_text,
          "Xcode Store builds compile the Store-managed update stub, not the direct downloader")
    check("Contents/Helpers/DaBin Update.app" in build_source and "DaBinUpdater.swift" not in project_text
          and "DaBinUpdateManifestURL" not in info,
          "The direct update helper and feed are limited to the standalone build path")

    check(info.get("LSMinimumSystemVersion") == "14.0", "Minimum supported macOS is 14.0")
    check(all(str(path.relative_to(ROOT)) in project_text for path in sources() + resources()),
          "Xcode project includes every current production source and required resource")
    generated = command([sys.executable, str(ROOT / "scripts/generate_project.py"), "--check"])
    check(generated.returncode == 0, "Generated project and shared scheme match the deterministic source inventory")
    check(project_text.count('ARCHS = "arm64";') == 6 and project_text.count('MACOSX_DEPLOYMENT_TARGET = "14.0";') == 6,
          "Debug and Release app/test/project configurations target ARM64 and macOS 14")
    check(project_text.count('SWIFT_TREAT_WARNINGS_AS_ERRORS = "YES";') == 6 and project_text.count('SWIFT_COMPILATION_MODE = "wholemodule";') == 3,
          "All configurations enforce Swift warnings; Release uses whole-module optimization")

    if not args.static_only:
        team = os.environ.get("DABIN_DEVELOPMENT_TEAM", "")
        check(bool(re.fullmatch(r"[A-Z0-9]{10}", team)), "Set DABIN_DEVELOPMENT_TEAM to your 10-character Apple Developer Team ID")
        xcode = command(["xcrun", "xcodebuild", "-version"])
        check(xcode.returncode == 0 and "Xcode " in xcode.stdout, "Full Xcode is selected and xcodebuild is available")
        for environment_key, plist_key, label in (
            ("DABIN_PRIVACY_POLICY_URL", "DaBinPrivacyPolicyURL", "published privacy policy"),
            ("DABIN_SUPPORT_URL", "DaBinSupportURL", "support page with real contact details"),
        ):
            value = os.environ.get(environment_key, info.get(plist_key, ""))
            check(public_https(value), f"Set {environment_key} to an HTTPS {label}; public reachability/content still require review")

    if args.app:
        app = args.app.resolve()
        bundled_info = read_plist(app / "Contents/Info.plist")
        executable = app / "Contents/MacOS" / bundled_info.get("CFBundleExecutable", "DaBin")
        architectures = command(["lipo", "-archs", str(executable)])
        check(architectures.returncode == 0 and architectures.stdout.strip() == "arm64", "Distribution app contains only ARM64 code")
        check(bundled_info.get("DaBinBuildConfiguration") == "Release", "Distribution app records a Release build")
        signature = command(["codesign", "-d", "--verbose=4", str(app)])
        check(signature.returncode == 0 and any(line.startswith(("Authority=Apple Distribution:", "Authority=3rd Party Mac Developer Application:")) for line in signature.stdout.splitlines()),
              "App has an App Store distribution signing identity, not ad-hoc/Developer ID signing")
        team_line = next((line.removeprefix("TeamIdentifier=") for line in signature.stdout.splitlines() if line.startswith("TeamIdentifier=")), "")
        check(team_line == os.environ.get("DABIN_DEVELOPMENT_TEAM") and bool(team_line), "Distribution signature matches the configured developer team")
        verified = command(["codesign", "--verify", "--deep", "--strict", str(app)])
        check(verified.returncode == 0, "Exact supplied app passes strict code-signature verification")
        claims = command(["codesign", "-d", "--entitlements", "-", "--xml", str(app)])
        try:
            xml_start = claims.stdout.index("<?xml")
            app_entitlements = plistlib.loads(claims.stdout[xml_start:].encode())
        except (ValueError, plistlib.InvalidFileException):
            app_entitlements = {}
        check(app_entitlements.get("com.apple.security.app-sandbox") is True, "Distribution signature includes App Sandbox")
        check(app_entitlements.get("com.apple.security.get-task-allow") is not True, "Distribution signature has no debugger entitlement")
        check(bundled_info.get("LSApplicationCategoryType") == "public.app-category.productivity", "Distribution app contains its Productivity category")
        for name in ("PrivacyInfo.xcprivacy", "PrivacyPolicy.md"):
            check((app / "Contents/Resources" / name).is_file(), f"Distribution app bundles {name}")
        for key in ("DaBinPrivacyPolicyURL", "DaBinSupportURL"):
            check(public_https(bundled_info.get(key, "")), f"Distribution app contains {key}")
        check("DaBinUpdateManifestURL" not in bundled_info and "DaBinDistributionChannel" not in bundled_info,
              "Distribution app has no direct GitHub update channel")
        check(not (app / "Contents/Helpers/DaBin Update.app").exists(),
              "Distribution app does not embed the direct update installer")

    if errors:
        print(f"\n{len(errors)} blocking check(s). No archive or upload was performed.")
        return 1
    if args.static_only:
        print("\nSource packaging checks passed. Signing, public URLs, Xcode, and App Store approval are not verified.")
    else:
        print("\nLocal preflight passed. Verify URLs, publisher/Bundle ID ownership, signing profiles, and App Store metadata; then validate the distribution archive in Xcode.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
