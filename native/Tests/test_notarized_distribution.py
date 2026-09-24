#!/usr/bin/env python3
"""Offline refusal and command-construction tests for public distribution."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/package_notarized_distribution.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("dabin_notarized_distribution", SCRIPT)
assert SPEC and SPEC.loader
distribution = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = distribution
SPEC.loader.exec_module(distribution)


IDENTITY = "Developer ID Application: DaBin Release (A1B2C3D4E5)"
TEAM = "A1B2C3D4E5"
GOOD_SIGNATURE = "\n".join([
    "Executable=/tmp/DaBin",
    "Identifier=com.dabin.mac",
    "Format=app bundle with Mach-O thin (arm64)",
    "CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+7 location=embedded",
    f"Authority={IDENTITY}",
    "Authority=Developer ID Certification Authority",
    "Authority=Apple Root CA",
    f"TeamIdentifier={TEAM}",
    "Timestamp=24 Sep 2026 at 12:00:00",
])


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def receipt_fixture(inventory: dict[str, str] | None = None) -> dict:
    inventory = inventory or {"Sources/Fixture.swift": "a" * 64}
    return {
        "schemaVersion": 1,
        "configuration": "Release",
        "target": "arm64-apple-macosx14.0",
        "version": "9.8.7",
        "buildNumber": "42",
        "executableSHA256": sha256_bytes(b"main executable"),
        "inputs": inventory,
        "sourceFingerprint": distribution.fingerprint(inventory),
        "embeddedUpdateHelper": True,
        "distributionChannel": "github",
        "strictSignatureVerifiedOnCleanCopy": True,
    }


def app_fixture(root: Path, receipt: dict) -> Path:
    app = root / "DaBin.app"
    main = app / "Contents/MacOS/DaBin"
    helper = app / "Contents/Helpers/DaBin Update.app"
    helper_executable = helper / "Contents/MacOS/DaBinUpdate"
    main.parent.mkdir(parents=True)
    helper_executable.parent.mkdir(parents=True)
    main.write_bytes(b"main executable")
    helper_executable.write_bytes(b"helper executable")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.dabin.mac",
        "CFBundleShortVersionString": receipt["version"],
        "CFBundleVersion": receipt["buildNumber"],
        "LSMinimumSystemVersion": "14.0",
        "DaBinBuildConfiguration": "Release",
        "DaBinSourceFingerprint": receipt["sourceFingerprint"],
    }))
    (helper / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.dabin.mac.updater.local",
        "CFBundleShortVersionString": receipt["version"],
        "CFBundleVersion": receipt["buildNumber"],
        "LSMinimumSystemVersion": "14.0",
    }))
    return app


class RecordingRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def run(self, arguments):
        command = [str(argument) for argument in arguments]
        self.calls.append(command)
        if command[:3] == ["xcrun", "stapler", "staple"]:
            return distribution.CommandResult(0, "The staple action worked!")
        if command[:3] == ["xcrun", "stapler", "validate"]:
            return distribution.CommandResult(0, "The validate action worked!")
        if command[0] == "spctl":
            return distribution.CommandResult(0, "accepted\nsource=Notarized Developer ID")
        if command[0] == "syspolicy_check":
            return distribution.CommandResult(0, "App passed all pre-distribution checks.")
        return distribution.CommandResult(0, "")

    def require(self, arguments, purpose):
        command = [str(argument) for argument in arguments]
        self.calls.append(command)
        if command[:3] == ["xcrun", "notarytool", "submit"]:
            return '{"id":"11111111-2222-3333-4444-555555555555","status":"Accepted"}'
        if command[:3] == ["codesign", "-d", "--verbose=4"]:
            return GOOD_SIGNATURE
        if command[:2] == ["lipo", "-archs"]:
            return "arm64\n"
        return ""


class ConfigurationTests(unittest.TestCase):
    def test_exact_developer_id_and_keychain_profile_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            configuration = distribution.DistributionConfiguration(
                IDENTITY,
                "DaBin-notary",
                Path(directory) / "new-output",
            )
            self.assertEqual(configuration.validate(), TEAM)

    def test_non_developer_id_and_ad_hoc_identities_are_refused(self):
        invalid = [
            "-",
            "Developer ID Application: -",
            "Apple Development: DaBin Release (A1B2C3D4E5)",
            "Apple Distribution: DaBin Release (A1B2C3D4E5)",
            "Developer ID Application: DaBin Release",
            " Developer ID Application: DaBin Release (A1B2C3D4E5)",
            "Developer ID Application: DaBin\nRelease (A1B2C3D4E5)",
        ]
        with tempfile.TemporaryDirectory() as directory:
            for identity in invalid:
                with self.subTest(identity=identity):
                    with self.assertRaises(distribution.DistributionError):
                        distribution.DistributionConfiguration(
                            identity,
                            "DaBin-notary",
                            Path(directory) / "new-output",
                        ).validate()

    def test_missing_or_option_shaped_notary_profile_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            for profile in ("", " DaBin-notary", "DaBin-notary ", "--keychain-profile", "bad\nprofile"):
                with self.subTest(profile=profile):
                    with self.assertRaises(distribution.DistributionError):
                        distribution.DistributionConfiguration(
                            IDENTITY,
                            profile,
                            Path(directory) / "new-output",
                        ).validate()

    def test_existing_output_is_preserved_and_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "existing"
            destination.mkdir()
            marker = destination / "keep.txt"
            marker.write_text("preserve", encoding="utf-8")
            with self.assertRaises(distribution.DistributionError):
                distribution.DistributionConfiguration(
                    IDENTITY,
                    "DaBin-notary",
                    destination,
                ).validate()
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_no_skip_notarization_option_exists(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                distribution.parse_arguments([
                    "--identity", IDENTITY,
                    "--notary-profile", "DaBin-notary",
                    "--output-directory", "/tmp/unused-dabin-test-output",
                    "--skip-notarization",
                ])

    def test_release_receipt_binds_schema_target_inputs_and_numeric_versions(self):
        inventory = {"Sources/Fixture.swift": "a" * 64}
        valid = receipt_fixture(inventory)
        self.assertIs(distribution.validate_release_receipt(valid, inventory), valid)
        for malformed in (None, [], "receipt"):
            with self.assertRaises(distribution.DistributionError):
                distribution.validate_release_receipt(malformed, inventory)
        mutations = {
            "schema": {"schemaVersion": 2},
            "target": {"target": "x86_64-apple-macosx14.0"},
            "version": {"version": "9.8.beta"},
            "too_many_version_parts": {"version": "9.8.7.6"},
            "path_version": {"version": "../9.8.7"},
            "zero_build": {"buildNumber": "0"},
            "dotted_build": {"buildNumber": "42.1"},
            "bad_sha": {"executableSHA256": "not-a-sha"},
            "missing_helper": {"embeddedUpdateHelper": False},
            "wrong_channel": {"distributionChannel": "store"},
        }
        for name, mutation in mutations.items():
            candidate = {**valid, **mutation}
            with self.subTest(name=name), self.assertRaises(distribution.DistributionError):
                distribution.validate_release_receipt(candidate, inventory)
        with self.assertRaises(distribution.DistributionError):
            distribution.validate_release_receipt(valid, {"changed": "b" * 64})

    def test_app_and_embedded_updater_match_receipt_and_arm64(self):
        receipt = receipt_fixture()
        with tempfile.TemporaryDirectory() as directory:
            app = app_fixture(Path(directory), receipt)
            runner = RecordingRunner()
            _, helper_sha = distribution.validate_app_shape(runner, app, receipt)
            self.assertEqual(helper_sha, sha256_bytes(b"helper executable"))
            self.assertEqual(sum(call[:2] == ["lipo", "-archs"] for call in runner.calls), 2)

    def test_app_validation_rejects_mutated_binary_wrong_arch_and_helper_identity(self):
        receipt = receipt_fixture()
        with tempfile.TemporaryDirectory() as directory:
            app = app_fixture(Path(directory), receipt)
            (app / "Contents/MacOS/DaBin").write_bytes(b"mutated")
            with self.assertRaises(distribution.DistributionError):
                distribution.validate_app_shape(RecordingRunner(), app, receipt)

        class WrongArchRunner(RecordingRunner):
            def require(self, arguments, purpose):
                command = [str(argument) for argument in arguments]
                if command[:2] == ["lipo", "-archs"]:
                    self.calls.append(command)
                    return "x86_64\n"
                return super().require(arguments, purpose)

        with tempfile.TemporaryDirectory() as directory:
            app = app_fixture(Path(directory), receipt)
            with self.assertRaises(distribution.DistributionError):
                distribution.validate_app_shape(WrongArchRunner(), app, receipt)

        with tempfile.TemporaryDirectory() as directory:
            app = app_fixture(Path(directory), receipt)
            helper_info = app / "Contents/Helpers/DaBin Update.app/Contents/Info.plist"
            payload = plistlib.loads(helper_info.read_bytes())
            payload["CFBundleIdentifier"] = "com.example.wrong"
            helper_info.write_bytes(plistlib.dumps(payload))
            with self.assertRaises(distribution.DistributionError):
                distribution.validate_app_shape(RecordingRunner(), app, receipt)

    def test_exclusive_publish_never_replaces_a_race_winner(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            staged = parent / ".owned-stage"
            staged.mkdir()
            (staged / "artifact").write_text("ours", encoding="utf-8")
            destination = parent / "release"
            destination.mkdir()
            marker = destination / "marker"
            marker.write_text("theirs", encoding="utf-8")
            with self.assertRaises(distribution.DistributionError):
                distribution.publish_exclusive(staged, destination)
            self.assertEqual(marker.read_text(encoding="utf-8"), "theirs")
            self.assertTrue(staged.exists())

    def test_exclusive_publish_moves_owned_staging_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            staged = parent / ".owned-stage"
            staged.mkdir()
            (staged / "artifact").write_text("verified", encoding="utf-8")
            destination = parent / "release"
            distribution.publish_exclusive(staged, destination)
            self.assertFalse(staged.exists())
            self.assertEqual((destination / "artifact").read_text(encoding="utf-8"), "verified")

    def test_exclusive_publish_rejects_different_parent_and_nonexistence_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "first"
            second = root / "second"
            first.mkdir()
            second.mkdir()
            staged = first / ".owned-stage"
            staged.mkdir()
            with self.assertRaises(distribution.DistributionError):
                distribution.publish_exclusive(staged, second / "release")

            destination = first / "release"

            def unsupported(_source, _destination, _flags):
                distribution.ctypes.set_errno(distribution.errno.ENOTSUP)
                return -1

            with self.assertRaises(distribution.DistributionError):
                distribution.publish_exclusive(staged, destination, unsupported)
            self.assertTrue(staged.exists())
            self.assertFalse(destination.exists())

    def test_final_zip_round_trip_uses_ditto_compatible_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "DaBin-9.8.7-AppleSilicon"
            package.mkdir()
            (package / "marker.txt").write_text("verified", encoding="utf-8")
            archive = root / "DaBin-9.8.7-AppleSilicon.zip"
            distribution.write_zip(distribution.CommandRunner(), package, archive)
            extracted = root / "extracted"
            distribution.extract_zip(distribution.CommandRunner(), archive, extracted)
            self.assertEqual(
                (extracted / package.name / "marker.txt").read_text(encoding="utf-8"),
                "verified",
            )


class SignatureAndPolicyTests(unittest.TestCase):
    def test_hardened_timestamped_requested_identity_is_accepted(self):
        distribution.validate_signature_details(GOOD_SIGNATURE, IDENTITY, TEAM)

    def test_ad_hoc_wrong_team_missing_runtime_or_timestamp_is_refused(self):
        invalid = [
            GOOD_SIGNATURE + "\nSignature=adhoc",
            GOOD_SIGNATURE.replace(f"TeamIdentifier={TEAM}", "TeamIdentifier=Z9Y8X7W6V5"),
            GOOD_SIGNATURE.replace("(runtime)", ""),
            GOOD_SIGNATURE.replace("Timestamp=24 Sep 2026 at 12:00:00", "Timestamp=none"),
            GOOD_SIGNATURE.replace(f"Authority={IDENTITY}", "Authority=Apple Development: Someone (A1B2C3D4E5)"),
        ]
        for details in invalid:
            with self.subTest(details=details):
                with self.assertRaises(distribution.DistributionError):
                    distribution.validate_signature_details(details, IDENTITY, TEAM)

    def test_notarytool_requires_accepted_status_and_submission_id(self):
        accepted = distribution.validate_notary_result('{"status":"Accepted","id":"submission-id"}')
        self.assertEqual(accepted, "submission-id")
        for payload in (
            "not-json",
            "[]",
            "null",
            '"Accepted"',
            '{"status":"Rejected","id":"submission-id"}',
            '{"status":"Invalid","id":"submission-id"}',
            '{"status":"Accepted"}',
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(distribution.DistributionError):
                    distribution.validate_notary_result(payload)

    def test_stapler_gatekeeper_and_syspolicy_fail_closed(self):
        with self.assertRaises(distribution.DistributionError):
            distribution.validate_stapler_result(distribution.CommandResult(1, "ticket missing"), "validate")
        with self.assertRaises(distribution.DistributionError):
            distribution.validate_gatekeeper_result(distribution.CommandResult(1, "rejected"))
        with self.assertRaises(distribution.DistributionError):
            distribution.validate_gatekeeper_result(distribution.CommandResult(0, "accepted\nsource=Developer ID"))
        with self.assertRaises(distribution.DistributionError):
            distribution.validate_syspolicy_result(
                distribution.CommandResult(0, "App has failed one or more pre-distribution checks.")
            )

    def test_packaged_bundle_requires_regular_stapled_ticket_and_executable_modes(self):
        receipt = receipt_fixture()
        with tempfile.TemporaryDirectory() as directory:
            app = app_fixture(Path(directory), receipt)
            main = app / "Contents/MacOS/DaBin"
            helper = app / "Contents/Helpers/DaBin Update.app/Contents/MacOS/DaBinUpdate"
            main.chmod(0o755)
            helper.chmod(0o755)
            ticket = app / "Contents/CodeResources"
            ticket.write_bytes(b"s8chfixture")
            distribution.verify_packaged_bundle(
                RecordingRunner(), app, IDENTITY, TEAM, receipt,
                sha256_bytes(b"main executable"), sha256_bytes(b"helper executable"),
            )
            ticket.write_bytes(b"not-a-ticket")
            with self.assertRaises(distribution.DistributionError):
                distribution.verify_packaged_bundle(
                    RecordingRunner(), app, IDENTITY, TEAM, receipt,
                    sha256_bytes(b"main executable"), sha256_bytes(b"helper executable"),
                )

    def test_signing_command_always_requests_runtime_and_timestamp(self):
        runner = RecordingRunner()
        distribution.sign_bundle(
            runner,
            Path("/tmp/DaBin.app"),
            IDENTITY,
            TEAM,
            Path("/tmp/DaBin.entitlements"),
        )
        signing = runner.calls[0]
        self.assertEqual(signing[:5], ["codesign", "--force", "--sign", IDENTITY, "--options"])
        self.assertIn("runtime", signing)
        self.assertIn("--timestamp", signing)
        self.assertIn("--entitlements", signing)
        self.assertNotIn("-", signing[3:4])

    def test_notarization_uses_stored_profile_then_all_local_policy_gates(self):
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            identifier = distribution.notarize_staple_and_assess(
                runner,
                Path("/tmp/DaBin.app"),
                "DaBin-notary",
                Path(directory),
                "application",
            )
        self.assertEqual(identifier, "11111111-2222-3333-4444-555555555555")
        commands = [" ".join(command) for command in runner.calls]
        submits = [command for command in commands if "notarytool submit" in command]
        self.assertEqual(len(submits), 1)
        self.assertIn("--keychain-profile DaBin-notary", submits[0])
        self.assertIn("--wait --output-format json", submits[0])
        self.assertTrue(any("stapler staple" in command for command in commands))
        self.assertTrue(any("stapler validate" in command for command in commands))
        self.assertTrue(any(command.startswith("spctl --assess") for command in commands))
        self.assertTrue(any(command.startswith("syspolicy_check distribution") for command in commands))

    def test_nested_signing_precedes_outer_signing_and_single_outer_notarization(self):
        events: list[tuple] = []
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            app = temporary / "DaBin.app"
            updater = app / "Contents/Helpers/DaBin Update.app"
            updater.mkdir(parents=True)

            def record_sign(_runner, bundle, identity, team, entitlements=None):
                events.append(("sign", bundle.name, entitlements is not None))

            def record_notary(_runner, bundle, profile, temp, label):
                events.append(("notarize", bundle.name, profile, label))
                return "submission-id"

            with mock.patch.object(distribution, "sign_bundle", side_effect=record_sign), \
                 mock.patch.object(distribution, "notarize_staple_and_assess", side_effect=record_notary):
                identifier = distribution.sign_notarize_and_validate_app(
                    runner, app, IDENTITY, TEAM, "DaBin-notary", temporary
                )

        self.assertEqual(identifier, "submission-id")
        self.assertEqual(events, [
            ("sign", "DaBin Update.app", False),
            ("sign", "DaBin.app", True),
            ("notarize", "DaBin.app", "DaBin-notary", "application"),
        ])
        self.assertEqual(
            sum("notarytool submit" in " ".join(call) for call in runner.calls),
            0,
            "The mocked outer notarizer is invoked once; no helper notarization occurs",
        )

    def test_exact_update_zip_is_installed_twice_and_backup_is_policy_checked(self):
        receipt = receipt_fixture()
        verified: list[Path] = []

        class InstallerRunner:
            def __init__(self):
                self.install_commands: list[list[str]] = []

            def require(self, arguments, purpose):
                command = [str(argument) for argument in arguments]
                self.install_commands.append(command)
                destination = Path(command[command.index("--destination") + 1])
                destination.mkdir(parents=True, exist_ok=True)
                if len(self.install_commands) == 1:
                    return "Installed DaBin 9.8.7 (42) at " + str(destination)
                backup = destination.parent / ".DaBinBackups/fixture.app"
                backup.mkdir(parents=True)
                return ("Installed DaBin 9.8.7 (42) at " + str(destination)
                        + "\nPrevious app backed up at " + str(backup))

        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            signed_app = temporary / "signed/DaBin.app"
            updater = signed_app / "Contents/Helpers/DaBin Update.app/Contents/MacOS/DaBinUpdate"
            updater.parent.mkdir(parents=True)
            updater.write_bytes(b"signed updater")
            update_zip = temporary / "DaBin-9.8.7-Update.zip"
            update_zip.write_bytes(b"exact generated update package")
            runner = InstallerRunner()

            def record_verification(_runner, bundle, *_arguments):
                verified.append(Path(bundle))

            with mock.patch.object(distribution, "verify_packaged_bundle", side_effect=record_verification), \
                 mock.patch.object(distribution, "file_manifest", return_value={"fixture": "a" * 64}):
                result = distribution.exercise_update_installer(
                    runner,
                    signed_app,
                    update_zip,
                    temporary,
                    IDENTITY,
                    TEAM,
                    receipt,
                    receipt["executableSHA256"],
                    sha256_bytes(b"signed updater"),
                )

        self.assertEqual(len(runner.install_commands), 2)
        for command in runner.install_commands:
            self.assertEqual(command[0], str(updater))
            self.assertIn("--package", command)
            self.assertIn(str(update_zip), command)
            self.assertIn("--package-sha256", command)
            self.assertIn("--non-interactive", command)
            self.assertIn("--no-launch", command)
        self.assertEqual([path.name for path in verified], ["DaBin.app", "DaBin.app", "fixture.app"])
        self.assertEqual(result["freshInstall"], "passed")
        self.assertEqual(result["replacement"], "passed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
