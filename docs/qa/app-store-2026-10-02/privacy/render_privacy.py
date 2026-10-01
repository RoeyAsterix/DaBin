#!/usr/bin/env python3
"""Docs-only privacy renderer using the current hash-verified final-QA module."""
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NATIVE = ROOT / "native"
sys.path.insert(0, str(NATIVE / "scripts"))
from project_inventory import TARGET, hashes, resources, sources


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    source_hashes = hashes(sources(False))
    resource_hashes = hashes(resources())
    candidates = []
    for stamp in (NATIVE / "build/qa-cache").glob("*/module-ready.json"):
        receipt = json.loads(stamp.read_text())
        if (receipt["inputs"]["sources"] == source_hashes
                and receipt["inputs"]["configuration"] == "Release"
                and receipt["inputs"]["target"] == TARGET
                and all(digest(stamp.parent / name) == sha for name, sha in receipt["outputs"].items())):
            candidates.append((stamp.stat().st_mtime, stamp, receipt))
    if not candidates:
        raise SystemExit("No current hash-verified Release QA module")
    _, stamp, receipt = max(candidates, key=lambda item: item[0])
    cache = stamp.parent
    with tempfile.TemporaryDirectory(prefix="dabin-privacy-docs-render-") as stage:
        app = Path(stage) / "DaBin Privacy Render.app"
        executable = app / "Contents/MacOS/ExportPrivacy"
        executable.parent.mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        shutil.copyfile(NATIVE / "Resources/PrivacyPolicy.md", app / "Contents/Resources/PrivacyPolicy.md")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.dabin.qa.privacy-render",
            "CFBundleExecutable": "ExportPrivacy", "CFBundlePackageType": "APPL", "LSUIElement": True,
        }))
        command = ["xcrun", "swiftc", "-swift-version", "5", "-O", "-target", TARGET,
            "-warnings-as-errors", "-module-cache-path", str(NATIVE / "build/ModuleCache"),
            "-parse-as-library", "-D", "DABIN_DIRECT_UPDATES", "-I", str(cache), "-L", str(cache),
            "-lDaBinTestCore", "-Xlinker", "-rpath", "-Xlinker", str(cache),
            str(HERE / "ExportPrivacy.swift"), "-o", str(executable)]
        compile_result = subprocess.run(command, cwd=NATIVE, text=True, capture_output=True)
        (HERE / "privacy-render-compile.log").write_text(compile_result.stdout + compile_result.stderr)
        compile_result.check_returncode()
        result = subprocess.run([str(executable), str(HERE)], cwd=NATIVE, text=True, capture_output=True, timeout=40)
        (HERE / "privacy-render.log").write_text(result.stdout + result.stderr)
        print(result.stdout + result.stderr, end="")
        result.check_returncode()
    if source_hashes != hashes(sources(False)) or resource_hashes != hashes(resources()):
        raise SystemExit("Production inputs changed during export: reject evidence")
    from PIL import Image
    names = [f"DABIN__PRIVACY__{mode}_{position}.png" for mode in ("LIGHT", "DARK") for position in ("TOP", "BOTTOM")]
    for name in names:
        with Image.open(HERE / name) as image:
            if image.size != (350, 440) or all(high - low < 30 for low, high in image.convert("RGB").getextrema()):
                raise SystemExit(f"Reject blank or wrongly sized render: {name}")
        with Image.open(HERE / name) as image:
            image.verify()
    manifest = {
        "schemaVersion": 1, "status": "NATIVE_SOURCE_MATCHED_RENDER_NOT_DISTRIBUTION_VERIFICATION",
        "checks": 11, "scope": "Docs-only adaptation preserves the original eleven test semantics and only changes the stale Choose Remove text assertion to Choose Move to Recently Deleted. Output filenames follow the requested canonical DABIN convention; the current full QA module supplies all production dependencies.",
        "sourceSHA256": source_hashes, "resourceSHA256": resource_hashes,
        "verifiedModuleReceipt": str(stamp.relative_to(ROOT)), "verifiedModuleReceiptSHA256": digest(stamp),
        "moduleOutputs": receipt["outputs"], "exportSourceSHA256": digest(HERE / "ExportPrivacy.swift"),
        "exportScriptSHA256": digest(Path(__file__)),
        "originalTestSHA256": digest(NATIVE / "Tests/PrivacyRenderTests.swift"),
        "originalScriptSHA256": digest(NATIVE / "scripts/render_privacy_qa.sh"),
        "outputs": {name: digest(HERE / name) for name in names + ["privacy-renders.json", "privacy-render.log", "privacy-render-compile.log"]},
        "fixturePrivacy": "Own offscreen nonactivating windows, current bundled policy, no personal archive/real clipboard/network/notifications/global input/installed app.",
        "visualReview": "Pending main-agent inspection of all four PNGs.",
        "notClaimed": "Exact App Store signed sandbox runtime verification, Apple approval, or the current whole build-inventory fingerprint.",
    }
    (HERE / "privacy-render-provenance.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("PASS: four current-policy native renders and source/module provenance saved")


if __name__ == "__main__":
    main()
