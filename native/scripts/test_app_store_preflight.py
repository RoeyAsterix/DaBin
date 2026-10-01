#!/usr/bin/env python3
"""Offline regressions for Store preparation; never touch keychain or installed apps."""

from copy import deepcopy
import datetime
from pathlib import Path
import tempfile
import unittest

import app_store_preflight as preflight
import build_store_candidate as candidate


class AppStorePreflightTests(unittest.TestCase):
    def test_minimal_source_entitlements_pass(self):
        self.assertEqual(preflight.entitlement_violations(preflight.SOURCE_ENTITLEMENTS, source=True), [])

    def test_every_required_capability_is_checked(self):
        for key in preflight.SOURCE_ENTITLEMENTS:
            with self.subTest(key=key):
                claims = deepcopy(preflight.SOURCE_ENTITLEMENTS)
                del claims[key]
                self.assertIn(key, preflight.entitlement_violations(claims))

    def test_integer_one_is_not_a_boolean_capability(self):
        claims = deepcopy(preflight.SOURCE_ENTITLEMENTS)
        claims["com.apple.security.app-sandbox"] = 1
        self.assertIn("com.apple.security.app-sandbox", preflight.entitlement_violations(claims))

    def test_debugger_entitlement_is_rejected(self):
        claims = {**preflight.SOURCE_ENTITLEMENTS, "com.apple.security.get-task-allow": True}
        self.assertIn("com.apple.security.get-task-allow", preflight.entitlement_violations(claims))

    def test_temporary_sandbox_exception_is_rejected(self):
        key = "com.apple.security.temporary-exception.files.absolute-path.read-write"
        claims = {**preflight.SOURCE_ENTITLEMENTS, key: ["/Users"]}
        self.assertIn(key, preflight.entitlement_violations(claims))

    def test_code_signing_exception_is_rejected(self):
        key = "com.apple.security.cs.disable-library-validation"
        claims = {**preflight.SOURCE_ENTITLEMENTS, key: True}
        self.assertIn(key, preflight.entitlement_violations(claims))

    def test_app_identifier_added_by_signing_is_allowed(self):
        claims = {**preflight.SOURCE_ENTITLEMENTS,
                  "com.apple.application-identifier": "8QG4967CSU.com.dabin.mac",
                  "com.apple.developer.team-identifier": "8QG4967CSU"}
        self.assertEqual(preflight.entitlement_violations(claims), [])

    def test_basic_development_archive_does_not_require_store_app_id_claims(self):
        self.assertEqual(preflight.signed_identifier_violations(
            preflight.SOURCE_ENTITLEMENTS, "8QG4967CSU", "com.dabin.mac", distribution=False), [])

    def test_distribution_does_require_matching_signed_app_id_claims(self):
        self.assertTrue(preflight.signed_identifier_violations(
            preflight.SOURCE_ENTITLEMENTS, "8QG4967CSU", "com.dabin.mac", distribution=True))
        claims = {**preflight.SOURCE_ENTITLEMENTS,
                  "com.apple.application-identifier": "8QG4967CSU.com.dabin.mac",
                  "com.apple.developer.team-identifier": "8QG4967CSU"}
        self.assertEqual(preflight.signed_identifier_violations(
            claims, "8QG4967CSU", "com.dabin.mac", distribution=True), [])
        claims["com.apple.application-identifier"] = "8QG4967CSU.com.other.mac"
        self.assertTrue(preflight.signed_identifier_violations(
            claims, "8QG4967CSU", "com.dabin.mac", distribution=True))

    def test_unreviewed_source_entitlement_is_rejected(self):
        key = "com.apple.security.device.camera"
        claims = {**preflight.SOURCE_ENTITLEMENTS, key: True}
        self.assertIn(key, preflight.entitlement_violations(claims, source=True))
        self.assertIn(key, preflight.entitlement_violations(claims))

    def privacy_manifest(self):
        return {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [],
                "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [
                    {"NSPrivacyAccessedAPIType": category,
                     "NSPrivacyAccessedAPITypeReasons": [reason]}
                    for category, reason in preflight.REQUIRED_PRIVACY_REASONS.items()
                ]}

    def test_manifest_covers_current_required_reasons(self):
        self.assertEqual(preflight.privacy_manifest_violations(self.privacy_manifest()), [])

    def test_missing_owned_file_timestamp_reason_fails(self):
        manifest = self.privacy_manifest()
        manifest["NSPrivacyAccessedAPITypes"].pop()
        self.assertIn("NSPrivacyAccessedAPICategoryFileTimestamp / C617.1",
                      preflight.privacy_manifest_violations(manifest))

    def test_tracking_or_collection_change_requires_review(self):
        for key, value in (("NSPrivacyTracking", True), ("NSPrivacyTrackingDomains", ["example.org"]),
                           ("NSPrivacyCollectedDataTypes", [{"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeOtherData"}])):
            with self.subTest(key=key):
                manifest = self.privacy_manifest()
                manifest[key] = value
                self.assertTrue(preflight.privacy_manifest_violations(manifest))

    def test_malformed_manifest_reasons_fail(self):
        manifest = self.privacy_manifest()
        manifest["NSPrivacyAccessedAPITypes"] = ["not a declaration"]
        self.assertTrue(preflight.privacy_manifest_violations(manifest))

    def profile(self):
        return {"TeamIdentifier": ["8QG4967CSU"], "Platform": ["OSX"],
                "ExpirationDate": datetime.datetime(2030, 1, 1),
                "Entitlements": {
                    "com.apple.application-identifier": "8QG4967CSU.com.dabin.mac",
                    "com.apple.developer.team-identifier": "8QG4967CSU",
                }}

    def test_current_matching_store_profile_passes(self):
        self.assertEqual(preflight.provisioning_profile_violations(self.profile(), "8QG4967CSU", "com.dabin.mac"), [])

    def test_mismatched_profile_team_or_app_fails(self):
        self.assertTrue(preflight.provisioning_profile_violations(self.profile(), "DIFFERENT0", "com.dabin.mac"))
        self.assertTrue(preflight.provisioning_profile_violations(self.profile(), "8QG4967CSU", "com.unrelated.mac"))

    def test_expired_profile_fails(self):
        profile = self.profile()
        profile["ExpirationDate"] = datetime.datetime(2020, 1, 1)
        self.assertIn("Provisioning profile is expired or missing an expiration",
                      preflight.provisioning_profile_violations(profile, "8QG4967CSU", "com.dabin.mac"))

    def test_nonstore_device_or_debug_profile_fails(self):
        for key, value in (("ProvisionedDevices", ["synthetic-device"]), ("ProvisionsAllDevices", True)):
            with self.subTest(key=key):
                profile = self.profile()
                profile[key] = value
                self.assertTrue(preflight.provisioning_profile_violations(profile, "8QG4967CSU", "com.dabin.mac"))
        profile = self.profile()
        profile["Entitlements"]["com.apple.security.get-task-allow"] = True
        self.assertTrue(preflight.provisioning_profile_violations(profile, "8QG4967CSU", "com.dabin.mac"))

    def test_recursive_direct_payload_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="dabin-store-test-") as directory:
            root = Path(directory)
            nested = root / "Contents/Resources/misleading-folder"
            nested.mkdir(parents=True)
            (nested / "DaBinUpdate").touch()
            (nested / "request.dabinupdate").touch()
            self.assertEqual(preflight.direct_update_payloads(root),
                             ["Contents/Resources/misleading-folder/DaBinUpdate",
                              "Contents/Resources/misleading-folder/request.dabinupdate"])

    def test_normal_resources_are_not_direct_payloads(self):
        with tempfile.TemporaryDirectory(prefix="dabin-store-test-") as directory:
            root = Path(directory)
            (root / "AppIcon.icns").touch()
            (root / "PrivacyInfo.xcprivacy").touch()
            self.assertEqual(preflight.direct_update_payloads(root), [])

    def test_store_stub_and_absence_of_direct_binary_marker(self):
        with tempfile.TemporaryDirectory(prefix="dabin-store-test-") as directory:
            executable = Path(directory) / "DaBin"
            executable.write_bytes(preflight.STORE_UPDATE_BINARY_MARKER)
            self.assertEqual(preflight.store_binary_violations(executable), [])
            for marker in preflight.DIRECT_UPDATE_BINARY_MARKERS:
                with self.subTest(marker=marker):
                    executable.write_bytes(preflight.STORE_UPDATE_BINARY_MARKER + b"\0" + marker)
                    self.assertIn("Direct GitHub downloader/installer implementation is present",
                                  preflight.store_binary_violations(executable))

    def test_missing_store_stub_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="dabin-store-test-") as directory:
            executable = Path(directory) / "DaBin"
            executable.write_bytes(b"ordinary non-Store executable")
            self.assertIn("Store-managed update implementation is missing",
                          preflight.store_binary_violations(executable))

    def test_unreadable_binary_is_rejected(self):
        self.assertTrue(preflight.store_binary_violations(Path("/nonexistent-dabin-test-executable")))

    def test_archive_never_enables_provisioning_downloads(self):
        text = (preflight.ROOT / "scripts/archive_app_store.sh").read_text()
        self.assertNotIn("-allowProvisioningUpdates", text)
        self.assertNotIn("-allowProvisioningDeviceRegistration", text)

    def test_release_metadata_is_explicit_and_not_direct(self):
        source = {"CFBundleIdentifier": "com.dabin.mac", "DaBinDistributionChannel": "github",
                  "DaBinUpdateManifestURL": "https://example.org/update.json"}
        result = candidate.candidate_info(source, "a" * 64)
        self.assertEqual(result["DaBinBuildConfiguration"], "Release")
        self.assertEqual(result["DaBinSourceFingerprint"], "a" * 64)
        self.assertNotIn("DaBinDistributionChannel", result)
        self.assertNotIn("DaBinUpdateManifestURL", result)
        self.assertIn("DaBinDistributionChannel", source)

    def test_xcode_resolves_source_configuration_marker(self):
        import plistlib
        info = plistlib.loads((preflight.ROOT / "Resources/Info.plist").read_bytes())
        self.assertEqual(info.get("DaBinBuildConfiguration"), "$(CONFIGURATION)")

    def test_unsigned_build_has_no_archive_account_or_upload_operation(self):
        arguments = candidate.build_arguments(Path("/tmp/owned-store-candidate"), Path("/tmp/Store-Info.plist"))
        self.assertEqual(arguments[-1], "build")
        self.assertIn("CODE_SIGNING_ALLOWED=NO", arguments)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", arguments)
        self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=", arguments)
        self.assertNotIn("-allowProvisioningUpdates", arguments)
        self.assertNotIn("archive", arguments)
        self.assertNotIn("-exportArchive", arguments)

    def test_candidate_refuses_workspace_root_and_nonbuild_destination(self):
        for destination in (candidate.ROOT, candidate.ROOT.parent,
                            candidate.ROOT / "build", Path("/tmp/store-candidate")):
            with self.subTest(destination=destination):
                with self.assertRaises(ValueError):
                    candidate.validate_output_directory(destination)

    def test_candidate_refuses_parent_directory_traversal(self):
        with self.assertRaises(ValueError):
            candidate.validate_output_directory(candidate.ROOT / "build/../Sources/new-candidate")

    def test_candidate_refuses_existing_output(self):
        with tempfile.TemporaryDirectory(prefix="dabin-store-existing-", dir=candidate.ROOT / "build") as directory:
            with self.assertRaises(ValueError):
                candidate.validate_output_directory(Path(directory))

    def test_candidate_accepts_new_build_leaf(self):
        destination = candidate.ROOT / "build" / "dabin-store-nonexistent-regression-output"
        self.assertEqual(candidate.validate_output_directory(destination), destination)

    def test_placeholder_urls_do_not_pass(self):
        for value in ("https://example.com/policy", "http://github.com/support", "https://127.0.0.1/support",
                      "https://localhost/support", "https://user:pass@github.com/support"):
            with self.subTest(value=value):
                self.assertFalse(preflight.public_https(value))


if __name__ == "__main__":
    unittest.main(verbosity=2)
