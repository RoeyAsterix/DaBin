#!/usr/bin/env python3
"""Stage one complete GitHub release with permanent latest-download aliases."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


REPOSITORY = "https://github.com/RoeyAsterix/DaBin"
LATEST_UPDATE_NAME = "DaBin-Latest-Update.zip"
LATEST_STANDALONE_NAME = "DaBin-Latest-AppleSilicon.zip"
ATTESTATION_NAME = "DISTRIBUTION-ATTESTATION.json"
VERSION_PATTERN = re.compile(r"\d+(?:\.\d+){0,2}")
BUILD_PATTERN = re.compile(r"[1-9]\d*")
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
DEVELOPER_ID_PATTERN = re.compile(
    r"Developer ID Application: .+ \(([A-Z0-9]{10})\)"
)
NOTARY_SUBMISSION_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
ATTESTATION_FIELDS = (
    "developerIDIdentity",
    "teamIdentifier",
    "localAdHocSigning",
    "hardenedRuntime",
    "trustedTimestamp",
    "notarizationValidated",
    "stapleValidated",
    "gatekeeperValidated",
    "notarySubmissionID",
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normal_file(path, label):
    path = path.absolute()
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"{label} must be a normal file: {path}")
    return path


def copy_exclusive(source, destination):
    with source.open("rb") as incoming, destination.open("xb") as outgoing:
        shutil.copyfileobj(incoming, outgoing)


def load_json(path, label):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"{label} is invalid: {error}")
    if not isinstance(value, dict):
        raise SystemExit(f"{label} must be a JSON object")
    return value


def validate_distribution_attestation(attestation, manifest, update, standalone):
    version = manifest["version"]
    build = manifest.get("buildNumber")
    identity = attestation.get("developerIDIdentity")
    identity_match = DEVELOPER_ID_PATTERN.fullmatch(identity) if isinstance(identity, str) else None
    if attestation.get("schemaVersion") != 1 \
            or attestation.get("version") != version \
            or attestation.get("buildNumber") != build \
            or identity_match is None \
            or attestation.get("teamIdentifier") != identity_match.group(1) \
            or NOTARY_SUBMISSION_PATTERN.fullmatch(str(attestation.get("notarySubmissionID", ""))) is None:
        raise SystemExit("The distribution attestation has an invalid release or Developer ID identity")
    if attestation.get("localAdHocSigning") is not False:
        raise SystemExit("The distribution attestation describes an ad-hoc build")
    for field in (
        "hardenedRuntime",
        "trustedTimestamp",
        "notarizationValidated",
        "stapleValidated",
        "gatekeeperValidated",
    ):
        if attestation.get(field) is not True:
            raise SystemExit(f"The distribution attestation did not pass {field}")

    expected_distribution = {field: attestation[field] for field in ATTESTATION_FIELDS}
    if manifest.get("distribution") != expected_distribution:
        raise SystemExit("The update manifest and distribution attestation disagree")
    for field in ("signedExecutableSHA256", "signedUpdaterExecutableSHA256"):
        value = attestation.get(field)
        if not isinstance(value, str) or SHA256_PATTERN.fullmatch(value) is None:
            raise SystemExit(f"The distribution attestation has no valid {field}")
    updater_qa = attestation.get("updaterQA")
    required_updater_gates = (
        "freshInstall",
        "replacement",
        "backup",
        "installedCodeSignature",
        "installedStaple",
        "installedGatekeeper",
        "installedSystemPolicy",
    )
    if not isinstance(updater_qa, dict) \
            or any(updater_qa.get(field) != "passed" for field in required_updater_gates) \
            or updater_qa.get("updateZIPSHA256") != sha256(update) \
            or manifest.get("updaterQA") != updater_qa:
        raise SystemExit("The distribution attestation lacks complete updater installation QA")

    artifacts = attestation.get("artifacts")
    expected_names = {update.name, standalone.name}
    if not isinstance(artifacts, dict) or set(artifacts) != expected_names:
        raise SystemExit("The distribution attestation does not name both exact packages")
    for artifact in (update, standalone):
        record = artifacts.get(artifact.name)
        if not isinstance(record, dict) \
                or set(record) != {"bytes", "sha256"} \
                or record.get("bytes") != artifact.stat().st_size \
                or record.get("sha256") != sha256(artifact):
            raise SystemExit(f"The distribution attestation does not match {artifact.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", type=Path, required=True,
                        help="Verified versioned DaBin-VERSION-Update.zip")
    parser.add_argument("--standalone", type=Path, required=True,
                        help="Verified versioned DaBin-VERSION-AppleSilicon.zip")
    parser.add_argument("--manifest", type=Path, required=True,
                        help="Verified public DaBin-update.json")
    parser.add_argument("--attestation", type=Path, required=True,
                        help="Fail-closed DISTRIBUTION-ATTESTATION.json")
    parser.add_argument("--guide", type=Path, required=True,
                        help="DaBin-Quick-Guide.pdf")
    parser.add_argument("--notes", type=Path, required=True,
                        help="RELEASE_NOTES_VERSION.md")
    parser.add_argument("--output-directory", type=Path, required=True,
                        help="New directory containing every asset to upload")
    args = parser.parse_args()

    update = normal_file(args.update, "--update")
    standalone = normal_file(args.standalone, "--standalone")
    manifest_path = normal_file(args.manifest, "--manifest")
    attestation_path = normal_file(args.attestation, "--attestation")
    guide = normal_file(args.guide, "--guide")
    notes = normal_file(args.notes, "--notes")
    destination = args.output_directory.absolute()
    if destination.exists() or destination.is_symlink():
        raise SystemExit("Output directory exists; preserved: " + str(destination))

    try:
        manifest = load_json(manifest_path, "The update manifest")
        version = manifest["version"]
        asset = manifest["asset"]
    except (KeyError, TypeError) as error:
        raise SystemExit("The update manifest is invalid: " + str(error))
    if manifest.get("schemaVersion") != 1 or not isinstance(version, str) \
            or VERSION_PATTERN.fullmatch(version) is None \
            or not isinstance(manifest.get("buildNumber"), str) \
            or BUILD_PATTERN.fullmatch(manifest["buildNumber"]) is None \
            or manifest.get("bundleIdentifier") != "com.dabin.mac" \
            or manifest.get("architecture") != "arm64" \
            or manifest.get("minimumMacOS") != "14.0" \
            or not isinstance(manifest.get("sourceFingerprint"), str) \
            or SHA256_PATTERN.fullmatch(manifest["sourceFingerprint"]) is None:
        raise SystemExit("The update manifest has an unsupported schema or version")

    update_name = f"DaBin-{version}-Update.zip"
    standalone_name = f"DaBin-{version}-AppleSilicon.zip"
    notes_name = f"RELEASE_NOTES_{version}.md"
    expected_url = f"{REPOSITORY}/releases/download/v{version}/{update_name}"
    update_hash = sha256(update)
    if update.name != update_name or standalone.name != standalone_name:
        raise SystemExit("The package filenames do not match the manifest version")
    if manifest_path.name != "DaBin-update.json" or attestation_path.name != ATTESTATION_NAME \
            or guide.name != "DaBin-Quick-Guide.pdf" \
            or notes.name != notes_name:
        raise SystemExit("The manifest, attestation, guide, or release-notes filename is not canonical")
    if not isinstance(asset, dict) or asset.get("name") != update_name \
            or asset.get("url") != expected_url or asset.get("bytes") != update.stat().st_size \
            or asset.get("sha256") != update_hash:
        raise SystemExit("The manifest does not describe the exact versioned update package")
    expected_release_page = f"{REPOSITORY}/releases/tag/v{version}"
    if manifest.get("releasePageURL") != expected_release_page:
        raise SystemExit("The update manifest has an unexpected release page")

    attestation = load_json(attestation_path, "The distribution attestation")
    validate_distribution_attestation(attestation, manifest, update, standalone)

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir()
    try:
        sources = {
            update_name: update,
            LATEST_UPDATE_NAME: update,
            standalone_name: standalone,
            LATEST_STANDALONE_NAME: standalone,
            "DaBin-update.json": manifest_path,
            ATTESTATION_NAME: attestation_path,
            "DaBin-Quick-Guide.pdf": guide,
            notes_name: notes,
        }
        for name, source in sources.items():
            copy_exclusive(source, destination / name)
        if sha256(destination / LATEST_UPDATE_NAME) != update_hash \
                or sha256(destination / LATEST_STANDALONE_NAME) != sha256(standalone):
            raise SystemExit("A permanent latest-download alias changed during staging")
    except BaseException:
        shutil.rmtree(destination, ignore_errors=True)
        raise

    print(f"Staged {len(sources)} verified release assets in {destination}")
    print(f"Permanent recommended download: {REPOSITORY}/releases/latest/download/{LATEST_UPDATE_NAME}")
    print(f"Permanent direct download: {REPOSITORY}/releases/latest/download/{LATEST_STANDALONE_NAME}")


if __name__ == "__main__":
    main()
