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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", type=Path, required=True,
                        help="Verified versioned DaBin-VERSION-Update.zip")
    parser.add_argument("--standalone", type=Path, required=True,
                        help="Verified versioned DaBin-VERSION-AppleSilicon.zip")
    parser.add_argument("--manifest", type=Path, required=True,
                        help="Verified public DaBin-update.json")
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
    guide = normal_file(args.guide, "--guide")
    notes = normal_file(args.notes, "--notes")
    destination = args.output_directory.absolute()
    if destination.exists() or destination.is_symlink():
        raise SystemExit("Output directory exists; preserved: " + str(destination))

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        version = manifest["version"]
        asset = manifest["asset"]
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise SystemExit("The update manifest is invalid: " + str(error))
    if manifest.get("schemaVersion") != 1 or not isinstance(version, str) \
            or re.fullmatch(r"\d+(?:\.\d+){0,2}", version) is None:
        raise SystemExit("The update manifest has an unsupported schema or version")

    update_name = f"DaBin-{version}-Update.zip"
    standalone_name = f"DaBin-{version}-AppleSilicon.zip"
    notes_name = f"RELEASE_NOTES_{version}.md"
    expected_url = f"{REPOSITORY}/releases/download/v{version}/{update_name}"
    update_hash = sha256(update)
    if update.name != update_name or standalone.name != standalone_name:
        raise SystemExit("The package filenames do not match the manifest version")
    if manifest_path.name != "DaBin-update.json" or guide.name != "DaBin-Quick-Guide.pdf" \
            or notes.name != notes_name:
        raise SystemExit("The manifest, guide, or release-notes filename is not canonical")
    if not isinstance(asset, dict) or asset.get("name") != update_name \
            or asset.get("url") != expected_url or asset.get("bytes") != update.stat().st_size \
            or asset.get("sha256") != update_hash:
        raise SystemExit("The manifest does not describe the exact versioned update package")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir()
    try:
        sources = {
            update_name: update,
            LATEST_UPDATE_NAME: update,
            standalone_name: standalone,
            LATEST_STANDALONE_NAME: standalone,
            "DaBin-update.json": manifest_path,
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
