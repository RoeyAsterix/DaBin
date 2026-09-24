#!/usr/bin/env python3
"""Create Developer ID signed and notarized DaBin packages for public download.

This is deliberately separate from the local/ad-hoc build and packaging tools.
It has no switch for skipping notarization, stapling, or Gatekeeper assessment,
and it does not make any output visible until every distribution gate passes.
"""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import datetime
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

from build_app import copy_permissions, copy_tree_without_metadata
from project_inventory import ROOT, TARGET, build_inventory, fingerprint


DEVELOPER_ID_PREFIX = "Developer ID Application: "
TEAM_IDENTIFIER_PATTERN = re.compile(r"\(([A-Z0-9]{10})\)$")
VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+){0,2}$")
BUILD_PATTERN = re.compile(r"^[1-9][0-9]*$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_MINIMUM_MACOS = "14.0"
EXPECTED_APP_IDENTIFIER = "com.dabin.mac"
EXPECTED_HELPER_IDENTIFIER = "com.dabin.mac.updater.local"
RENAME_EXCL = 0x00000004


class DistributionError(RuntimeError):
    """A release gate failed; no public package may be emitted."""


@dataclass(frozen=True)
class DistributionConfiguration:
    identity: str
    notary_profile: str
    output_directory: Path
    guide: Path | None = None

    def validate(self) -> str:
        identity = self.identity.strip()
        if identity != self.identity or not identity.startswith(DEVELOPER_ID_PREFIX):
            raise DistributionError(
                "--identity must be an exact 'Developer ID Application: … (TEAMID)' identity"
            )
        if any(ord(character) < 32 for character in identity):
            raise DistributionError("The Developer ID identity contains invalid control characters")
        if identity == DEVELOPER_ID_PREFIX + "-" or identity.endswith(": -"):
            raise DistributionError("Ad-hoc signing is forbidden for public distribution")
        team_match = TEAM_IDENTIFIER_PATTERN.search(identity)
        if not team_match:
            raise DistributionError("The Developer ID identity must end with a 10-character team ID")

        profile = self.notary_profile
        if not profile or profile != profile.strip() or profile.startswith("-"):
            raise DistributionError("--notary-profile must name a stored notarytool keychain profile")
        if any(character in profile for character in ("\0", "\n", "\r")):
            raise DistributionError("The notarytool keychain profile name contains invalid characters")

        destination = self.output_directory.expanduser().absolute()
        if destination.exists() or destination.is_symlink():
            raise DistributionError(f"Output directory already exists; preserved: {destination}")
        if self.guide is not None:
            guide = self.guide.expanduser().absolute()
            if guide.is_symlink() or not guide.is_file() or guide.suffix.lower() != ".pdf":
                raise DistributionError("--guide must point to a normal PDF file")
        return team_match.group(1)


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str


class CommandRunner:
    def run(self, arguments: list[object]) -> CommandResult:
        command = [str(argument) for argument in arguments]
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        return CommandResult(completed.returncode, completed.stdout)

    def require(self, arguments: list[object], purpose: str) -> str:
        result = self.run(arguments)
        if result.returncode != 0:
            detail = result.output.strip() or f"exit status {result.returncode}"
            raise DistributionError(f"{purpose} failed: {detail}")
        return result.output


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_symlinks(path: Path, label: str) -> None:
    if path.is_symlink() or any(candidate.is_symlink() for candidate in path.rglob("*")):
        raise DistributionError(f"Refusing a symbolic link in {label}")


def validate_identity_is_installed(runner: CommandRunner, identity: str) -> None:
    listing = runner.require(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        "Developer ID identity lookup",
    )
    quoted_identity = f'"{identity}"'
    matching_lines = [line for line in listing.splitlines() if quoted_identity in line]
    if len(matching_lines) != 1:
        raise DistributionError(
            "The exact Developer ID Application identity is not available once in the login keychain"
        )
    if "CSSMERR_" in matching_lines[0] or "REVOKED" in matching_lines[0].upper():
        raise DistributionError("The selected Developer ID Application identity is not valid")


def validate_signature_details(details: str, identity: str, team_identifier: str) -> None:
    lines = [line.strip() for line in details.splitlines()]
    authorities = [line.removeprefix("Authority=") for line in lines if line.startswith("Authority=")]
    if not authorities or authorities[0] != identity:
        raise DistributionError("Bundle is not signed by the requested Developer ID Application identity")
    if "Signature=adhoc" in details or not any(line == f"TeamIdentifier={team_identifier}" for line in lines):
        raise DistributionError("Ad-hoc or wrong-team code signature is forbidden")
    if "(runtime)" not in details:
        raise DistributionError("The hardened runtime flag is missing from the code signature")
    timestamp = next((line.removeprefix("Timestamp=") for line in lines if line.startswith("Timestamp=")), "")
    if not timestamp or timestamp.lower() in {"none", "n/a"}:
        raise DistributionError("A trusted signing timestamp is required")


def validate_notary_result(payload: str) -> str:
    try:
        result = json.loads(payload)
    except (json.JSONDecodeError, TypeError) as error:
        raise DistributionError("notarytool did not return valid JSON") from error
    if not isinstance(result, dict):
        raise DistributionError("notarytool returned JSON with an unexpected top-level type")
    if result.get("status") != "Accepted":
        status = result.get("status", "missing")
        identifier = result.get("id", "unknown")
        message = result.get("message", "Apple did not accept this submission")
        raise DistributionError(f"Notarization {identifier} was {status}: {message}")
    identifier = result.get("id")
    if not isinstance(identifier, str) or not identifier.strip():
        raise DistributionError("The accepted notarization response has no submission ID")
    return identifier


def validate_stapler_result(result: CommandResult, action: str) -> None:
    if result.returncode != 0 or "worked" not in result.output.lower():
        detail = result.output.strip() or f"exit status {result.returncode}"
        raise DistributionError(f"Stapler {action} failed: {detail}")


def validate_gatekeeper_result(result: CommandResult) -> None:
    normalized = result.output.lower()
    if result.returncode != 0 or "accepted" not in normalized or "notarized developer id" not in normalized:
        detail = result.output.strip() or f"exit status {result.returncode}"
        raise DistributionError(f"Gatekeeper did not accept a notarized Developer ID app: {detail}")


def validate_syspolicy_result(result: CommandResult) -> None:
    normalized = result.output.lower()
    if result.returncode != 0 or "passed all pre-distribution checks" not in normalized:
        detail = result.output.strip() or f"exit status {result.returncode}"
        raise DistributionError(f"macOS distribution policy rejected the app: {detail}")


def validate_release_receipt(receipt: object, inventory: dict[str, str]) -> dict:
    if not isinstance(receipt, dict):
        raise DistributionError("The Release build receipt must be a JSON object")
    if receipt.get("schemaVersion") != 1:
        raise DistributionError("Unsupported Release build receipt schema")
    if receipt.get("configuration") != "Release" or receipt.get("target") != TARGET:
        raise DistributionError("Public distribution requires the exact Release ARM64 target receipt")
    version = receipt.get("version")
    build = receipt.get("buildNumber")
    if not isinstance(version, str) or VERSION_PATTERN.fullmatch(version) is None:
        raise DistributionError("The Release version must contain only numeric dot-separated components")
    if not isinstance(build, str) or BUILD_PATTERN.fullmatch(build) is None:
        raise DistributionError("The Release build number must be a positive integer")
    executable_sha = receipt.get("executableSHA256")
    if not isinstance(executable_sha, str) or SHA256_PATTERN.fullmatch(executable_sha) is None:
        raise DistributionError("The Release receipt has no valid executable SHA-256")
    recorded_inputs = receipt.get("inputs")
    if not isinstance(recorded_inputs, dict) or recorded_inputs != inventory:
        raise DistributionError("The Release receipt inputs do not match the current source inventory")
    recorded_fingerprint = receipt.get("sourceFingerprint")
    if recorded_fingerprint != fingerprint(recorded_inputs) or recorded_fingerprint != fingerprint(inventory):
        raise DistributionError("The Release build receipt is stale or internally inconsistent")
    if receipt.get("embeddedUpdateHelper") is not True or receipt.get("distributionChannel") != "github":
        raise DistributionError("The Release receipt is not for the direct update channel")
    if receipt.get("strictSignatureVerifiedOnCleanCopy") is not True:
        raise DistributionError("The Release receipt lacks clean-copy signature verification")
    return receipt


def validate_app_shape(
    runner: CommandRunner,
    app: Path,
    receipt: dict,
    expected_main_sha256: str | None = None,
    expected_helper_sha256: str | None = None,
) -> tuple[dict, str]:
    reject_symlinks(app, "the DaBin application")
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise DistributionError("DaBin.app has no valid Info.plist") from error
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != EXPECTED_APP_IDENTIFIER:
        raise DistributionError("Unexpected DaBin application bundle identifier")
    if info.get("DaBinBuildConfiguration") != "Release":
        raise DistributionError("Public distribution requires an optimized Release build")
    if info.get("CFBundleShortVersionString") != receipt.get("version") or info.get("CFBundleVersion") != receipt.get("buildNumber"):
        raise DistributionError("DaBin.app version does not match the build receipt")
    if info.get("DaBinSourceFingerprint") != receipt.get("sourceFingerprint"):
        raise DistributionError("DaBin.app does not match the recorded source fingerprint")
    if info.get("LSMinimumSystemVersion") != EXPECTED_MINIMUM_MACOS:
        raise DistributionError("DaBin.app has an unexpected minimum macOS version")
    executable = app / "Contents/MacOS/DaBin"
    if not executable.is_file() or executable.is_symlink():
        raise DistributionError("DaBin.app has no normal main executable")
    expected_main_sha256 = expected_main_sha256 or receipt["executableSHA256"]
    if sha256(executable) != expected_main_sha256:
        raise DistributionError("DaBin executable bytes do not match the expected signed build")
    architectures = runner.require(["lipo", "-archs", executable], "DaBin architecture inspection").strip()
    if architectures != "arm64":
        raise DistributionError("DaBin.app must contain exactly one ARM64 architecture")

    helper = app / "Contents/Helpers/DaBin Update.app"
    reject_symlinks(helper, "the embedded updater")
    try:
        helper_info = plistlib.loads((helper / "Contents/Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise DistributionError("The embedded updater has no valid Info.plist") from error
    expected_version = receipt["version"]
    expected_build = receipt["buildNumber"]
    if (not isinstance(helper_info, dict)
            or helper_info.get("CFBundleIdentifier") != EXPECTED_HELPER_IDENTIFIER
            or helper_info.get("CFBundleShortVersionString") != expected_version
            or helper_info.get("CFBundleVersion") != expected_build
            or helper_info.get("LSMinimumSystemVersion") != EXPECTED_MINIMUM_MACOS):
        raise DistributionError("The embedded updater identity, version, build, or minimum macOS is invalid")
    helper_executable = helper / "Contents/MacOS/DaBinUpdate"
    if not helper_executable.is_file() or helper_executable.is_symlink():
        raise DistributionError("The embedded updater has no normal executable")
    helper_sha = sha256(helper_executable)
    if expected_helper_sha256 is not None and helper_sha != expected_helper_sha256:
        raise DistributionError("The embedded updater executable changed during packaging")
    helper_architectures = runner.require(
        ["lipo", "-archs", helper_executable], "Embedded updater architecture inspection"
    ).strip()
    if helper_architectures != "arm64":
        raise DistributionError("The embedded updater must contain exactly one ARM64 architecture")
    return info, helper_sha


def sign_bundle(
    runner: CommandRunner,
    bundle: Path,
    identity: str,
    team_identifier: str,
    entitlements: Path | None = None,
) -> None:
    arguments: list[object] = [
        "codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp",
    ]
    if entitlements is not None:
        arguments += ["--entitlements", entitlements]
    arguments.append(bundle)
    runner.require(arguments, f"Developer ID signing of {bundle.name}")
    runner.require(["codesign", "--verify", "--deep", "--strict", bundle], f"Strict signature verification of {bundle.name}")
    details = runner.require(["codesign", "-d", "--verbose=4", bundle], f"Signature inspection of {bundle.name}")
    validate_signature_details(details, identity, team_identifier)


def create_notary_archive(runner: CommandRunner, bundle: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise DistributionError(f"Temporary notarization archive unexpectedly exists: {destination}")
    runner.require(
        ["ditto", "-c", "-k", "--keepParent", bundle, destination],
        f"Notarization archive creation for {bundle.name}",
    )


def notarize_staple_and_assess(
    runner: CommandRunner,
    bundle: Path,
    profile: str,
    temporary: Path,
    label: str,
) -> str:
    archive = temporary / f"{label}-notary-submission.zip"
    create_notary_archive(runner, bundle, archive)
    response = runner.require(
        ["xcrun", "notarytool", "submit", archive, "--keychain-profile", profile,
         "--wait", "--output-format", "json"],
        f"Apple notarization of {bundle.name}",
    )
    submission_id = validate_notary_result(response)

    staple = runner.run(["xcrun", "stapler", "staple", "-v", bundle])
    validate_stapler_result(staple, "staple")
    validate = runner.run(["xcrun", "stapler", "validate", "-v", bundle])
    validate_stapler_result(validate, "validate")
    gatekeeper = runner.run(["spctl", "--assess", "--type", "execute", "--verbose=4", bundle])
    validate_gatekeeper_result(gatekeeper)
    syspolicy = runner.run(["syspolicy_check", "distribution", bundle])
    validate_syspolicy_result(syspolicy)
    return submission_id


def write_zip(runner: CommandRunner, source_directory: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise DistributionError(f"ZIP output unexpectedly exists: {destination}")
    runner.require(
        ["ditto", "-c", "-k", "--keepParent", source_directory, destination],
        f"ZIP creation for {source_directory.name}",
    )
    validate_zip_entries(destination)


def validate_zip_entries(source: Path) -> None:
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise DistributionError(f"ZIP integrity validation failed: {source.name}")
        for member in archive.infolist():
            member_path = Path(member.filename)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise DistributionError(f"Unsafe path in generated ZIP: {member.filename}")


def extract_zip(runner: CommandRunner, source: Path, destination: Path) -> None:
    validate_zip_entries(source)
    if destination.exists() or destination.is_symlink():
        raise DistributionError(f"ZIP extraction destination unexpectedly exists: {destination}")
    destination.mkdir(parents=True)
    runner.require(["ditto", "-x", "-k", source, destination], f"ZIP extraction of {source.name}")
    reject_symlinks(destination, f"the extracted {source.name}")


def publish_exclusive(staged_directory: Path, destination: Path, rename_function=None) -> None:
    """Atomically publish a same-volume directory without replacing a race winner."""
    if (not staged_directory.is_absolute() or not destination.is_absolute()
            or staged_directory.parent != destination.parent):
        raise DistributionError("Exclusive publication requires same-parent staging")
    if rename_function is None:
        libc = ctypes.CDLL(None, use_errno=True)
        rename_function = libc.renamex_np
        rename_function.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        rename_function.restype = ctypes.c_int
    ctypes.set_errno(0)
    result = rename_function(os.fsencode(staged_directory), os.fsencode(destination), RENAME_EXCL)
    if result == 0:
        return
    error_number = ctypes.get_errno()
    if error_number == errno.EEXIST:
        raise DistributionError(f"Output directory already exists; preserved: {destination}")
    raise DistributionError(
        f"Exclusive output publication failed ({error_number}): {os.strerror(error_number)}"
    )


def file_manifest(directory: Path) -> dict[str, str]:
    return {
        str(path.relative_to(directory)): sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file()
    }


def read_release_receipt() -> dict:
    receipt_path = ROOT / "build/build-receipt.json"
    try:
        receipt = json.loads(receipt_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise DistributionError("A valid Release build receipt is required") from error
    return validate_release_receipt(receipt, build_inventory())


def verify_packaged_bundle(
    runner: CommandRunner,
    bundle: Path,
    identity: str,
    team_identifier: str,
    receipt: dict,
    expected_main_sha256: str,
    expected_helper_sha256: str,
) -> None:
    validate_app_shape(runner, bundle, receipt, expected_main_sha256, expected_helper_sha256)
    ticket = bundle / "Contents/CodeResources"
    if (not ticket.is_file() or ticket.is_symlink()
            or ticket.read_bytes()[:4] != b"s8ch"):
        raise DistributionError("The notarization ticket is not stored as a normal stapled app ticket")
    executables = [
        bundle / "Contents/MacOS/DaBin",
        bundle / "Contents/Helpers/DaBin Update.app/Contents/MacOS/DaBinUpdate",
    ]
    if any(not os.access(executable, os.X_OK) for executable in executables):
        raise DistributionError("A packaged executable lost its executable mode")
    runner.require(["codesign", "--verify", "--deep", "--strict", bundle], f"Extracted signature verification of {bundle.name}")
    details = runner.require(["codesign", "-d", "--verbose=4", bundle], f"Extracted signature inspection of {bundle.name}")
    validate_signature_details(details, identity, team_identifier)
    validate_stapler_result(
        runner.run(["xcrun", "stapler", "validate", "-v", bundle]),
        "validate extracted package",
    )
    validate_gatekeeper_result(
        runner.run(["spctl", "--assess", "--type", "execute", "--verbose=4", bundle])
    )
    validate_syspolicy_result(runner.run(["syspolicy_check", "distribution", bundle]))


def sign_notarize_and_validate_app(
    runner: CommandRunner,
    app: Path,
    identity: str,
    team_identifier: str,
    notary_profile: str,
    temporary: Path,
) -> str:
    embedded_updater = app / "Contents/Helpers/DaBin Update.app"
    if not embedded_updater.is_dir():
        raise DistributionError("The direct-channel Release build has no embedded updater")

    # Code-sign inside out. The embedded updater is a nested code object, so
    # its final Developer ID signature must exist before the enclosing DaBin
    # application receives its final signature.
    sign_bundle(runner, embedded_updater, identity, team_identifier)
    sign_bundle(
        runner,
        app,
        identity,
        team_identifier,
        ROOT / "Resources/DaBin.entitlements",
    )

    # Submit exactly one archive containing the complete outer application.
    # Stapling and launch-policy assessment also target that outer application.
    submission = notarize_staple_and_assess(
        runner, app, notary_profile, temporary, "application"
    )
    runner.require(
        ["codesign", "--verify", "--deep", "--strict", embedded_updater],
        "Nested updater signature verification after notarization",
    )
    validate_signature_details(
        runner.require(
            ["codesign", "-d", "--verbose=4", embedded_updater],
            "Nested updater signature inspection after notarization",
        ),
        identity,
        team_identifier,
    )
    return submission


def exercise_update_installer(
    runner: CommandRunner,
    packaged_app: Path,
    update_zip: Path,
    temporary: Path,
    identity: str,
    team_identifier: str,
    receipt: dict,
    expected_main_sha256: str,
    expected_helper_sha256: str,
) -> dict[str, str]:
    """Run the shipped updater's exact ZIP/copy path twice in an isolated home."""
    updater = packaged_app / "Contents/Helpers/DaBin Update.app/Contents/MacOS/DaBinUpdate"
    if not updater.is_file() or updater.is_symlink():
        raise DistributionError("The signed embedded updater executable is unavailable for QA")
    update_sha = sha256(update_zip)
    expected_files = file_manifest(packaged_app)
    qa_root = temporary / "updater-qa-home"
    qa_root.mkdir()
    destination = qa_root / "Applications/DaBin.app"
    command: list[object] = [
        updater,
        "--package", update_zip,
        "--package-sha256", update_sha,
        "--destination", destination,
        "--non-interactive",
        "--no-launch",
    ]

    first = runner.require(command, "Isolated fresh installation through DaBin Update")
    if f"Installed DaBin {receipt['version']} ({receipt['buildNumber']})" not in first:
        raise DistributionError("The updater did not confirm the isolated fresh installation")
    if "Previous app backed up at" in first:
        raise DistributionError("A fresh updater installation unexpectedly reported a backup")
    verify_packaged_bundle(
        runner, destination, identity, team_identifier, receipt,
        expected_main_sha256, expected_helper_sha256,
    )
    backups = destination.parent / ".DaBinBackups"
    if backups.exists() and any(backups.iterdir()):
        raise DistributionError("A fresh updater installation unexpectedly created a backup")

    second = runner.require(command, "Isolated replacement through DaBin Update")
    backup_apps = sorted(backups.glob("*.app")) if backups.is_dir() and not backups.is_symlink() else []
    if len(backup_apps) != 1:
        raise DistributionError("Updater QA did not preserve exactly one previous application")
    if f"Previous app backed up at {backup_apps[0]}" not in second:
        raise DistributionError("The updater did not confirm the exact replacement backup")
    for installed in (destination, backup_apps[0]):
        if file_manifest(installed) != expected_files:
            raise DistributionError("The updater's no-metadata copy changed packaged application bytes")
        verify_packaged_bundle(
            runner, installed, identity, team_identifier, receipt,
            expected_main_sha256, expected_helper_sha256,
        )
    return {
        "freshInstall": "passed",
        "replacement": "passed",
        "backup": "passed",
        "installedCodeSignature": "passed",
        "installedStaple": "passed",
        "installedGatekeeper": "passed",
        "installedSystemPolicy": "passed",
        "updateZIPSHA256": update_sha,
    }


def package_public_distribution(configuration: DistributionConfiguration, runner: CommandRunner) -> Path:
    team_identifier = configuration.validate()
    validate_identity_is_installed(runner, configuration.identity)
    receipt = read_release_receipt()
    source_app = ROOT / "build/DaBin.app"
    _, source_helper_sha256 = validate_app_shape(runner, source_app, receipt)
    reject_symlinks(source_app, "the Release build")

    output_directory = configuration.output_directory.expanduser().absolute()
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    if output_directory.parent.is_symlink():
        raise DistributionError("Refusing a symbolic-link output parent")

    version = str(receipt["version"])
    build_number = str(receipt["buildNumber"])
    created_at = datetime.datetime.now(datetime.timezone.utc).isoformat()

    with tempfile.TemporaryDirectory(
        prefix=".dabin-notarized-distribution-", dir=output_directory.parent
    ) as temporary_name, tempfile.TemporaryDirectory(
        prefix=".dabin-release-staging-", dir=output_directory.parent
    ) as staged_output_name:
        temporary = Path(temporary_name)
        staged_output = Path(staged_output_name)
        signed_app = temporary / "signed/DaBin.app"
        signed_app.parent.mkdir()
        copy_tree_without_metadata(source_app, signed_app)
        validate_app_shape(
            runner, signed_app, receipt, receipt["executableSHA256"], source_helper_sha256
        )
        app_submission = sign_notarize_and_validate_app(
            runner,
            signed_app,
            configuration.identity,
            team_identifier,
            configuration.notary_profile,
            temporary,
        )
        distribution_main_sha256 = sha256(signed_app / "Contents/MacOS/DaBin")
        distribution_helper_sha256 = sha256(
            signed_app / "Contents/Helpers/DaBin Update.app/Contents/MacOS/DaBinUpdate"
        )
        validate_app_shape(
            runner, signed_app, receipt, distribution_main_sha256, distribution_helper_sha256
        )

        common_attestation = {
            "developerIDIdentity": configuration.identity,
            "teamIdentifier": team_identifier,
            "localAdHocSigning": False,
            "hardenedRuntime": True,
            "trustedTimestamp": True,
            "notarizationValidated": True,
            "stapleValidated": True,
            "gatekeeperValidated": True,
            "notarySubmissionID": app_submission,
        }

        standalone = temporary / f"DaBin-{version}-AppleSilicon"
        standalone.mkdir()
        copy_tree_without_metadata(signed_app, standalone / "DaBin.app")
        if configuration.guide:
            copy_permissions(configuration.guide.expanduser().absolute(), standalone / "DaBin-Quick-Guide.pdf")
        (standalone / "README.txt").write_text(
            f"DaBin {version} ({build_number}) for Apple Silicon\n\n"
            "Requires macOS 14 or later. Move DaBin.app to ~/Applications, then open it.\n"
            "This application is Developer ID signed, Apple notarized, and carries a stapled ticket.\n"
            "If macOS does not identify it as a notarized DaBin application, stop and report the release issue.\n",
            encoding="utf-8",
        )
        standalone_manifest = {
            "schemaVersion": 2,
            "createdAtUTC": created_at,
            "version": version,
            "buildNumber": build_number,
            "configuration": "Release",
            "architecture": "arm64",
            "minimumMacOS": "14.0",
            "installationTarget": "~/Applications/DaBin.app",
            "sourceFingerprint": receipt["sourceFingerprint"],
            "signedExecutableSHA256": distribution_main_sha256,
            "signedUpdaterExecutableSHA256": distribution_helper_sha256,
            **common_attestation,
        }
        standalone_manifest["files"] = file_manifest(standalone)
        (standalone / "PACKAGE-MANIFEST.json").write_text(
            json.dumps(standalone_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        standalone_zip = staged_output / f"DaBin-{version}-AppleSilicon.zip"
        write_zip(runner, standalone, standalone_zip)

        update = temporary / f"DaBin-{version}-Update"
        update.mkdir()
        copy_tree_without_metadata(signed_app, update / "DaBin.app")
        if configuration.guide:
            copy_permissions(configuration.guide.expanduser().absolute(), update / "DaBin-Quick-Guide.pdf")
        (update / "README.txt").write_text(
            f"DaBin {version} ({build_number}) verified update payload for Apple Silicon\n\n"
            "This verified package is consumed by DaBin's built-in updater. For a first installation,\n"
            "use the AppleSilicon package and move DaBin.app to ~/Applications.\n"
            "DaBin.app is Developer ID signed, Apple notarized, and carries a stapled ticket.\n"
            "If macOS does not identify DaBin as notarized, stop and report the release issue.\n",
            encoding="utf-8",
        )
        update_manifest = {
            "schemaVersion": 2,
            "createdAtUTC": created_at,
            "version": version,
            "buildNumber": build_number,
            "architecture": "arm64",
            "minimumMacOS": "14.0",
            "targetInstallation": "~/Applications/DaBin.app",
            "preservesArchive": True,
            "backsUpExistingApplication": True,
            "supportsInAppGitHubDownload": True,
            "sourceFingerprint": receipt["sourceFingerprint"],
            "signedExecutableSHA256": distribution_main_sha256,
            "signedUpdaterExecutableSHA256": distribution_helper_sha256,
            **common_attestation,
        }
        update_manifest["files"] = file_manifest(update)
        (update / "UPDATE-MANIFEST.json").write_text(
            json.dumps(update_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        update_zip = staged_output / f"DaBin-{version}-Update.zip"
        write_zip(runner, update, update_zip)

        # Re-extract and repeat signature, ticket and Gatekeeper checks on the
        # exact bytes that would be uploaded.
        extracted = temporary / "round-trip"
        extract_zip(runner, standalone_zip, extracted / "standalone")
        extract_zip(runner, update_zip, extracted / "update")
        extracted_standalone = extracted / "standalone" / standalone.name / "DaBin.app"
        extracted_update_app = extracted / "update" / update.name / "DaBin.app"
        for bundle in (extracted_standalone, extracted_update_app):
            verify_packaged_bundle(
                runner, bundle, configuration.identity, team_identifier, receipt,
                distribution_main_sha256, distribution_helper_sha256,
            )

        updater_qa = exercise_update_installer(
            runner,
            extracted_update_app,
            update_zip,
            temporary,
            configuration.identity,
            team_identifier,
            receipt,
            distribution_main_sha256,
            distribution_helper_sha256,
        )

        update_sha256 = sha256(update_zip)
        release_manifest = {
            "schemaVersion": 1,
            "bundleIdentifier": "com.dabin.mac",
            "version": version,
            "buildNumber": build_number,
            "architecture": "arm64",
            "minimumMacOS": "14.0",
            "sourceFingerprint": receipt["sourceFingerprint"],
            "releasePageURL": f"https://github.com/RoeyAsterix/DaBin/releases/tag/v{version}",
            "distribution": common_attestation,
            "updaterQA": updater_qa,
            "asset": {
                "name": update_zip.name,
                "url": f"https://github.com/RoeyAsterix/DaBin/releases/download/v{version}/{update_zip.name}",
                "bytes": update_zip.stat().st_size,
                "sha256": update_sha256,
            },
        }
        (staged_output / "DaBin-update.json").write_text(
            json.dumps(release_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        (staged_output / "DISTRIBUTION-ATTESTATION.json").write_text(
            json.dumps({
                "schemaVersion": 1,
                "createdAtUTC": created_at,
                "version": version,
                "buildNumber": build_number,
                "artifacts": {
                    standalone_zip.name: {"bytes": standalone_zip.stat().st_size, "sha256": sha256(standalone_zip)},
                    update_zip.name: {"bytes": update_zip.stat().st_size, "sha256": update_sha256},
                },
                "updaterQA": updater_qa,
                "signedExecutableSHA256": distribution_main_sha256,
                "signedUpdaterExecutableSHA256": distribution_helper_sha256,
                **common_attestation,
            }, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        # Recheck the complete receipt/source binding after the network work,
        # then atomically publish the process-owned hidden staging directory.
        validate_release_receipt(receipt, build_inventory())
        publish_exclusive(staged_output, output_directory)

    return output_directory


def parse_arguments(argv: list[str] | None = None) -> DistributionConfiguration:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="Exact Developer ID Application identity")
    parser.add_argument(
        "--notary-profile",
        required=True,
        help="notarytool keychain profile created with xcrun notarytool store-credentials",
    )
    parser.add_argument("--output-directory", type=Path, required=True, help="New directory for verified packages")
    parser.add_argument("--guide", type=Path, help="Optional PDF guide included in both packages")
    args = parser.parse_args(argv)
    return DistributionConfiguration(args.identity, args.notary_profile, args.output_directory, args.guide)


def main(argv: list[str] | None = None) -> int:
    try:
        configuration = parse_arguments(argv)
        output = package_public_distribution(configuration, CommandRunner())
    except (DistributionError, OSError) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 1
    print(f"Created Developer ID signed, notarized, stapled, Gatekeeper-approved packages: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
