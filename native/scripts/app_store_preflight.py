#!/usr/bin/env python3
"""Offline release checks. Passing does not replace Xcode/App Store validation."""
import argparse
import datetime
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
from project_inventory import sources, resources, build_inventory, fingerprint

ROOT = Path(__file__).resolve().parents[1]
errors = []
SOURCE_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.network.client": True,
}
DIRECT_UPDATE_BINARY_MARKERS = (
    b"Checking GitHub Releases",
    b"The verified installer is open. Choose Update to continue.",
    b"The built-in DaBin installer did not pass code-signature validation.",
)
STORE_UPDATE_BINARY_MARKER = b"Updates for this build are delivered through the Mac App Store."
REQUIRED_PRIVACY_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1",
    "NSPrivacyAccessedAPICategorySystemBootTime": "35F9.1",
    "NSPrivacyAccessedAPICategoryFileTimestamp": "C617.1",
}


def entitlement_violations(claims, *, source=False):
    """Validate the deliberately small capability set, not arbitrary exceptions."""
    violations = [key for key, value in SOURCE_ENTITLEMENTS.items()
                  if claims.get(key) is not value]
    if claims.get("com.apple.security.get-task-allow") is True:
        violations.append("com.apple.security.get-task-allow")
    for key, value in claims.items():
        if not value or key in SOURCE_ENTITLEMENTS:
            continue
        if source or key.startswith("com.apple.security."):
            violations.append(key)
    return sorted(set(violations))


def privacy_manifest_violations(manifest):
    result = []
    if manifest.get("NSPrivacyTracking") is not False:
        result.append("Tracking declaration changed")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        result.append("Tracking domains are not empty")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        result.append("Data collection differs from the reviewed on-device design")
    values = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(values, list) or any(not isinstance(value, dict) for value in values):
        return result + ["Required-reason declarations are not a list of dictionaries"]
    reasons = {value.get("NSPrivacyAccessedAPIType"): value.get("NSPrivacyAccessedAPITypeReasons")
               for value in values}
    for category, reason in REQUIRED_PRIVACY_REASONS.items():
        if not isinstance(reasons.get(category), list) or reason not in reasons[category]:
            result.append(category + " / " + reason)
    return result


def provisioning_profile_violations(profile, team, bundle_identifier, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    result = []
    if team not in profile.get("TeamIdentifier", []):
        result.append("Provisioning team does not match")
    claims = profile.get("Entitlements", {})
    if claims.get("com.apple.application-identifier") != team + "." + bundle_identifier:
        result.append("Provisioning application identifier does not match")
    if claims.get("com.apple.developer.team-identifier") != team:
        result.append("Provisioning entitlement team does not match")
    if claims.get("com.apple.security.get-task-allow") is True:
        result.append("Provisioning profile enables debugger attachment")
    if "OSX" not in profile.get("Platform", []):
        result.append("Provisioning profile is not for macOS")
    expires = profile.get("ExpirationDate")
    if isinstance(expires, datetime.datetime) and expires.tzinfo is None:
        expires = expires.replace(tzinfo=datetime.timezone.utc)
    if not isinstance(expires, datetime.datetime) or expires <= now:
        result.append("Provisioning profile is expired or missing an expiration")
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        result.append("Provisioning profile is not restricted to Store distribution")
    return result


def signed_identifier_violations(claims, team, bundle_identifier, *, distribution):
    # A standard development archive with only basic sandbox capabilities can
    # legitimately have no app-ID claims/profile. Store export must add them.
    if not distribution:
        return []
    expected = {"com.apple.application-identifier": team + "." + bundle_identifier,
                "com.apple.developer.team-identifier": team}
    return [key for key, value in expected.items() if claims.get(key) != value]


def direct_update_payloads(app):
    """Inspect filenames recursively; a renamed helper directory cannot bypass this."""
    names = {"DaBin Update.app", "DaBinUpdate", "DaBinUpdater", "DaBin-update.json"}
    return sorted(str(path.relative_to(app)) for path in app.rglob("*")
                  if path.name in names or path.suffix.lower() == ".dabinupdate")


def store_binary_violations(executable):
    try:
        data = executable.read_bytes()
    except OSError as error:
        return [f"Executable could not be inspected: {error}"]
    result = []
    if STORE_UPDATE_BINARY_MARKER not in data:
        result.append("Store-managed update implementation is missing")
    if any(marker in data for marker in DIRECT_UPDATE_BINARY_MARKERS):
        result.append("Direct GitHub downloader/installer implementation is present")
    return result


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


def paths_with_extended_attribute(root, attribute):
    """Return bundle paths carrying an attribute without following symlinks."""
    result = command(["/usr/bin/xattr", "-r", str(root)])
    if result.returncode != 0:
        raise OSError(result.stdout.strip() or "xattr could not inspect the application bundle")
    suffix = f": {attribute}"
    return [Path(line.removesuffix(suffix))
            for line in result.stdout.splitlines() if line.endswith(suffix)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true", help="Check source packaging only; does not report release readiness")
    inspected_apps = parser.add_mutually_exclusive_group()
    inspected_apps.add_argument("--app", type=Path,
                                help="Also inspect a distribution-signed app bundle; an ad-hoc, development, or Developer ID app must fail")
    inspected_apps.add_argument("--archive-app", type=Path,
                                help="Also inspect the development-signed app inside an Xcode archive before Organizer export")
    inspected_apps.add_argument("--unsigned-app", type=Path,
                                help="Inspect an unsigned Store compile for packaging only; never reports distribution readiness")
    args = parser.parse_args()
    if args.static_only and (args.app or args.archive_app or args.unsigned_app):
        parser.error("--static-only cannot be combined with an app inspection")
    errors.clear()
    signing = json.loads((ROOT / "Config/AppStoreSigning.json").read_text())
    configured_team = signing.get("developmentTeam", "")
    configured_bundle_identifier = signing.get("bundleIdentifier", "")
    effective_team = os.environ.get("DABIN_DEVELOPMENT_TEAM", configured_team)
    info = read_plist(ROOT / "Resources/Info.plist")
    entitlements = read_plist(ROOT / "Resources/DaBin.entitlements")
    manifest = read_plist(ROOT / "Resources/PrivacyInfo.xcprivacy")
    check(bool(re.fullmatch(r"[A-Z0-9]{10}", configured_team)), "Apple Developer Team ID is configured")
    check(effective_team == configured_team, "Environment Team ID matches the checked-in signing configuration")
    check(bool(re.fullmatch(r"[A-Za-z0-9.-]+", configured_bundle_identifier)), "App Store bundle identifier is configured")
    check(info.get("CFBundleIdentifier") == configured_bundle_identifier, "Info.plist uses the configured App Store bundle identifier")
    check(info.get("LSApplicationCategoryType") == "public.app-category.productivity", "Productivity category is configured")
    check(bool(info.get("NSHumanReadableCopyright")), "Copyright is present (publisher must confirm ownership)")
    check(bool(re.fullmatch(r"\d+(?:\.\d+){0,2}", info.get("CFBundleShortVersionString", ""))), "Marketing version has a numeric release format")
    check(bool(re.fullmatch(r"\d+(?:\.\d+){0,2}", info.get("CFBundleVersion", ""))), "Build number has a numeric release format")
    check(info.get("DaBinBuildConfiguration") == "$(CONFIGURATION)",
          "Xcode resolves the source build-configuration marker deterministically")
    check(info.get("ITSAppUsesNonExemptEncryption") is False,
          "Export compliance declares only absent or exempt encryption")
    check(entitlements.get("com.apple.security.app-sandbox") is True, "App Sandbox is enabled")
    check(not entitlements.get("com.apple.security.get-task-allow"), "Source entitlement file does not allow debugger attachment")
    check(not entitlement_violations(entitlements, source=True),
          "Source capabilities match the minimal reviewed sandbox entitlement set")
    check(manifest.get("NSPrivacyTracking") is False, "Bundled manifest declares no tracking")
    check(isinstance(manifest.get("NSPrivacyCollectedDataTypes"), list), "Manifest contains the collected-data declaration")
    manifest_errors = privacy_manifest_violations(manifest)
    check(not manifest_errors,
          "Privacy manifest covers preferences, elapsed time and app-owned file timestamps without tracking/collection"
          + (": " + "; ".join(manifest_errors) if manifest_errors else ""))
    check((ROOT / "Resources/PrivacyPolicy.md").is_file(), "Readable in-app privacy policy resource exists")
    project = ROOT / "DaBin.xcodeproj/project.pbxproj"
    project_text = project.read_text() if project.is_file() else ""
    check(f'DEVELOPMENT_TEAM = "{configured_team}";' in project_text,
          "Release build uses the configured Apple Developer Team")
    check(f'PRODUCT_BUNDLE_IDENTIFIER = "{configured_bundle_identifier}";' in project_text,
          "Xcode app target uses the configured App Store bundle identifier")
    for name in ("PrivacyInfo.xcprivacy", "PrivacyPolicy.md", "PrivacyInformation.swift"):
        check(name in project_text, f"Xcode project includes {name}")

    update_source = (ROOT / "Sources/DaBin/SoftwareUpdateService.swift").read_text()
    build_source = (ROOT / "scripts/build_app.py").read_text()
    check("#if DABIN_DIRECT_UPDATES" in update_source and "DABIN_DIRECT_UPDATES" not in project_text,
          "Xcode Store builds compile the Store-managed update stub, not the direct downloader")
    check("Contents/Helpers/DaBin Update.app" in build_source and "DaBinUpdater.swift" not in project_text
          and "DaBinUpdateManifestURL" not in info,
          "The direct update helper and feed are limited to the standalone build path")
    archive_source = (ROOT / "scripts/archive_app_store.sh").read_text()
    check("-allowProvisioningUpdates" not in archive_source
          and "-allowProvisioningDeviceRegistration" not in archive_source,
          "Archive helper never silently downloads provisioning assets or registers devices")

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
        xcode = command(["xcrun", "xcodebuild", "-version"])
        check(xcode.returncode == 0 and "Xcode " in xcode.stdout, "Full Xcode is selected and xcodebuild is available")
        for environment_key, plist_key, label in (
            ("DABIN_PRIVACY_POLICY_URL", "DaBinPrivacyPolicyURL", "published privacy policy"),
            ("DABIN_SUPPORT_URL", "DaBinSupportURL", "support page with real contact details"),
        ):
            value = os.environ.get(environment_key, info.get(plist_key, ""))
            check(public_https(value), f"An HTTPS {label} is configured; public reachability/content still require review")

    inspected_app = args.app or args.archive_app or args.unsigned_app
    if inspected_app:
        app = inspected_app.resolve()
        bundled_info = read_plist(app / "Contents/Info.plist")
        executable = app / "Contents/MacOS" / bundled_info.get("CFBundleExecutable", "DaBin")
        architectures = command(["lipo", "-archs", str(executable)])
        check(architectures.returncode == 0 and architectures.stdout.strip() == "arm64", "Distribution app contains only ARM64 code")
        check(bundled_info.get("DaBinBuildConfiguration") == "Release", "Distribution app records a Release build")
        check(bundled_info.get("CFBundleIdentifier") == configured_bundle_identifier,
              "Inspected app uses the configured bundle identifier")
        check(all(bundled_info.get(key) == info.get(key) for key in
                  ("CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion")),
              "Inspected version, build and minimum macOS match the current source")
        check(bundled_info.get("DaBinSourceFingerprint") == fingerprint(build_inventory()),
              "Inspected app fingerprint matches the current production build inputs")
        binary_errors = store_binary_violations(executable)
        check(not binary_errors, "Inspected binary contains the Store update stub and no direct downloader"
              + (": " + "; ".join(binary_errors) if binary_errors else ""))
        if not args.unsigned_app:
            signature = command(["codesign", "-d", "--verbose=4", str(app)])
            if args.archive_app:
                expected_authorities = ("Authority=Apple Development:", "Authority=Mac Developer:")
                signing_message = "Archive app has an Apple development signing identity for Organizer export"
            else:
                expected_authorities = ("Authority=Apple Distribution:",
                                        "Authority=3rd Party Mac Developer Application:")
                signing_message = "App has an App Store distribution signing identity, not ad-hoc/development/Developer ID signing"
            check(signature.returncode == 0 and any(line.startswith(expected_authorities)
                                                    for line in signature.stdout.splitlines()),
                  signing_message)
            team_line = next((line.removeprefix("TeamIdentifier=") for line in signature.stdout.splitlines() if line.startswith("TeamIdentifier=")), "")
            check(team_line == effective_team and bool(team_line), "Distribution signature matches the configured developer team")
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
            check(not entitlement_violations(app_entitlements),
                  "Signed capabilities retain required scope without temporary or code-signing exceptions")
            if args.app:
                check(not signed_identifier_violations(app_entitlements, effective_team,
                                                       configured_bundle_identifier, distribution=True),
                      "Signed application and entitlement team identifiers match the configured app")
                profile_path = app / "Contents/embedded.provisionprofile"
                decoded = command(["security", "cms", "-D", "-i", str(profile_path)])
                try:
                    profile_xml = decoded.stdout[decoded.stdout.index("<?xml"):]
                    profile = plistlib.loads(profile_xml.encode()) if decoded.returncode == 0 else {}
                except (ValueError, plistlib.InvalidFileException):
                    profile = {}
                profile_errors = provisioning_profile_violations(profile, effective_team, configured_bundle_identifier)
                check(not profile_errors,
                      "Distribution app embeds a current macOS Store profile for the configured app/team"
                      + (": " + "; ".join(profile_errors) if profile_errors else ""))
                with tempfile.TemporaryDirectory(prefix="dabin-store-public-cert-") as temporary:
                    cert_prefix = str(Path(temporary) / "certificate-")
                    extracted = command(["codesign", "-d", "--extract-certificates", cert_prefix, str(app)])
                    leaf = Path(cert_prefix + "0")
                    leaf_hash = hashlib.sha256(leaf.read_bytes()).digest() if leaf.is_file() else None
                    allowed_hashes = [hashlib.sha256(value).digest()
                                      for value in profile.get("DeveloperCertificates", []) if isinstance(value, bytes)]
                    check(extracted.returncode == 0 and leaf_hash is not None and leaf_hash in allowed_hashes,
                          "Distribution signature certificate is included in the embedded provisioning profile")
        check(bundled_info.get("LSApplicationCategoryType") == "public.app-category.productivity", "Distribution app contains its Productivity category")
        for name in ("PrivacyInfo.xcprivacy", "PrivacyPolicy.md"):
            check((app / "Contents/Resources" / name).is_file(), f"Distribution app bundles {name}")
        for key in ("DaBinPrivacyPolicyURL", "DaBinSupportURL"):
            check(public_https(bundled_info.get(key, "")), f"Distribution app contains {key}")
        check("DaBinUpdateManifestURL" not in bundled_info and "DaBinDistributionChannel" not in bundled_info,
              "Distribution app has no direct GitHub update channel")
        check(not (app / "Contents/Helpers/DaBin Update.app").exists(),
              "Distribution app does not embed the direct update installer")
        check(not direct_update_payloads(app),
              "Inspected app contains no direct update helper, manifest or handoff payload")
        bundled_manifest = read_plist(app / "Contents/Resources/PrivacyInfo.xcprivacy")
        check(bundled_manifest == manifest,
              "Inspected privacy manifest matches the reviewed source declaration")
        for name in ("PrivacyPolicy.md", "AppIcon.icns"):
            bundled_path = app / "Contents/Resources" / name
            check(bundled_path.is_file()
                  and bundled_path.read_bytes() == (ROOT / "Resources" / name).read_bytes(),
                  f"Inspected app bundles the exact current {name}")
        try:
            quarantined = paths_with_extended_attribute(app, "com.apple.quarantine")
        except OSError as error:
            check(False, f"Distribution app extended attributes can be inspected: {error}")
        else:
            check(not quarantined,
                  "Distribution app contains no quarantined files"
                  + (f" ({quarantined[0]}" + (f" and {len(quarantined) - 1} more" if len(quarantined) > 1 else "") + ")"
                     if quarantined else ""))

    if errors:
        print(f"\n{len(errors)} blocking check(s). No archive or upload was performed.")
        return 1
    if args.unsigned_app:
        print("\nUnsigned Store packaging checks passed. This is NOT a distribution candidate; signing, sandbox runtime behavior, archive validation, upload and Apple review remain unverified.")
    elif args.static_only:
        print("\nSource packaging checks passed. Signing, public URLs, Xcode, and App Store approval are not verified.")
    else:
        print("\nLocal preflight passed. Verify URLs, publisher/Bundle ID ownership, signing profiles, and App Store metadata; then validate the distribution archive in Xcode.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
