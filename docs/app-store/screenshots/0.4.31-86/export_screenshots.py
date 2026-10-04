#!/usr/bin/env python3
"""Render current native App Store screenshot drafts from a verified QA module.

Adapted from design/onepager/export_guide_assets.py. This does not replace a
distribution-signed sandbox screenshot comparison or perform an upload.
"""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
NATIVE = HERE.parents[3] / "native/build/store-preparation-20261004/native"
sys.path.insert(0, str(NATIVE / "scripts"))
from project_inventory import TARGET, hashes, resources, sources

EXPECTED_VERSION = "0.4.31"
EXPECTED_BUILD = "86"
FILENAMES = [
    "DABIN__APP_STORE__01_INBOX.png",
    "DABIN__APP_STORE__02_PROJECTS.png",
    "DABIN__APP_STORE__03_FOCUS.png",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", required=True,
                        help="Compile/render only after the coordinated final QA has completed")
    parser.parse_args()
    info = plistlib.loads((NATIVE / "Resources/Info.plist").read_bytes())
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (EXPECTED_VERSION, EXPECTED_BUILD):
        raise SystemExit("Version/build changed: create a new screenshot-draft directory, do not overwrite this set.")

    current_sources = hashes(sources(False))
    current_resources = hashes(resources())
    verified = []
    for stamp in (NATIVE / "build/qa-cache").glob("*/module-ready.json"):
        try:
            receipt = json.loads(stamp.read_text())
            if (receipt["inputs"]["sources"] != current_sources
                    or receipt["inputs"]["configuration"] != "Release"
                    or receipt["inputs"].get("distribution") != "app-store"
                    or receipt["inputs"]["target"] != TARGET):
                continue
            if all(digest(stamp.parent / name) == sha for name, sha in receipt["outputs"].items()):
                verified.append((stamp.stat().st_mtime, stamp, receipt))
        except (OSError, KeyError, ValueError):
            continue
    if not verified:
        raise SystemExit("No current hash-verified Release QA module. Complete coordinated final QA first.")
    _, stamp, receipt = max(verified, key=lambda item: item[0])
    cache = stamp.parent
    destination = NATIVE / "build/app-store-screenshot-export" / HERE.name
    destination.mkdir(parents=True, exist_ok=True)
    for resource in resources():
        shutil.copyfile(resource, destination / resource.name)
    executable = destination / "ExportScreenshots"
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET,
        "-module-cache-path", str(NATIVE / "build/ModuleCache"), "-warnings-as-errors", "-O",
        "-parse-as-library", "-I", str(cache), "-L", str(cache),
        "-lDaBinTestCore", "-Xlinker", "-rpath", "-Xlinker", str(cache),
        str(HERE / "ExportScreenshots.swift"), "-o", str(executable)]
    subprocess.run(command, cwd=NATIVE, check=True)
    subprocess.run([str(executable), str(HERE)], cwd=NATIVE, check=True, timeout=90)
    if hashes(sources(False)) != current_sources or hashes(resources()) != current_resources:
        raise SystemExit("Production inputs changed during export; reject these screenshot drafts.")

    from PIL import Image
    screenshots = []
    for name in FILENAMES:
        path = HERE / name
        with Image.open(path) as rendered:
            if rendered.size != (1440, 900) or rendered.mode not in ("RGB", "RGBA"):
                raise SystemExit(f"Wrong dimensions/color/alpha for {name}: {rendered.size}, {rendered.mode}")
            rendered.load()
            if rendered.mode == "RGBA" and rendered.getchannel("A").getextrema() != (255, 255):
                raise SystemExit(f"Native canvas is not fully opaque: {name}")
            rgb = rendered.convert("RGB")
            if all(high - low < 30 for low, high in rgb.getextrema()):
                raise SystemExit(f"Native capture is blank or nearly blank: reject {name}")
        rgb.save(path, "PNG")
        with Image.open(path) as rendered:
            if rendered.mode != "RGB" or "transparency" in rendered.info:
                raise SystemExit(f"Opaque RGB export failed for {name}")
            rendered.verify()
        screenshots.append({"file": name, "sha256": digest(path), "width": 1440, "height": 900,
                            "colorMode": "RGB", "alpha": False})
    manifest = {
        "schemaVersion": 1, "version": EXPECTED_VERSION, "build": EXPECTED_BUILD,
        "distribution": "app-store", "frozenNativeRoot": str(NATIVE),
        "status": "DRAFT_NOT_VERIFIED_AGAINST_DISTRIBUTION_BINARY",
        "dimensions": [1440, 900], "colorMode": "RGB", "alpha": False,
        "fixturePrivacy": "Fictional temporary archive, named isolated preferences, own nonactivating offscreen windows, no personal data/clipboard/network/notification delivery/global input/installed-app actions.",
        "renderMethod": "Production BoardView, RobotAppFrameView and canonical Quiet Orbit RobotCharacterView rendered natively at 1x. Only the backdrop/headline/subtitle are marketing composition; app controls and contents are actual native UI.",
        "sourceSHA256": current_sources, "resourceSHA256": current_resources,
        "exportSourceSHA256": digest(HERE / "ExportScreenshots.swift"),
        "exportScriptSHA256": digest(Path(__file__)),
        "verifiedModuleReceipt": str(stamp.relative_to(NATIVE)), "moduleOutputs": receipt["outputs"],
        "compilerArguments": [str(arg) for arg in command],
        "nativeRenderManifest": "native-renders.json", "nativeRenderManifestSHA256": digest(HERE / "native-renders.json"),
        "screenshots": screenshots,
        "visualReview": "Pending all-three-image inspection by the main agent.",
        "submissionGate": "Compare every UI view with the exact distribution-signed sandbox candidate and confirm metadata rights before upload. No upload performed.",
        "preserved": ["../1440x900/", "../../../../design/onepager/assets/"],
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("PASS: three current-native fictional RGB 1440x900 screenshot drafts:", HERE)


if __name__ == "__main__":
    main()
