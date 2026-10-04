#!/usr/bin/env python3
"""Export fictional guide UI from a hash-verified current native QA module."""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
NATIVE = HERE.parents[1] / "native"
sys.path.insert(0, str(NATIVE / "scripts"))
from project_inventory import TARGET, hashes, resources, sources


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    current_sources = hashes(sources(False))
    verified = []
    for stamp in (NATIVE / "build/qa-cache").glob("*/module-ready.json"):
        try:
            receipt = json.loads(stamp.read_text())
            if receipt["inputs"]["sources"] != current_sources or receipt["inputs"]["configuration"] != "Release":
                continue
            if all(digest(stamp.parent / name) == sha for name, sha in receipt["outputs"].items()):
                verified.append((stamp.stat().st_mtime, stamp, receipt))
        except (OSError, KeyError, ValueError):
            continue
    if not verified:
        raise SystemExit("No current hash-verified Release QA module. Build the native QA module first.")
    _, stamp, receipt = max(verified, key=lambda item: item[0])
    cache = stamp.parent
    destination = NATIVE / "build/guide-export"
    destination.mkdir(parents=True, exist_ok=True)
    for resource in resources():
        shutil.copyfile(resource, destination / resource.name)
    executable = destination / "ExportGuide"
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET,
        "-module-cache-path", str(NATIVE / "build/ModuleCache"), "-warnings-as-errors", "-O",
        "-D", "DABIN_DIRECT_UPDATES", "-parse-as-library", "-I", str(cache), "-L", str(cache),
        "-lDaBinTestCore", "-Xlinker", "-rpath", "-Xlinker", str(cache), str(HERE / "ExportGuide.swift"), "-o", str(executable)]
    subprocess.run(command, cwd=NATIVE, check=True)
    output = HERE / "assets"
    subprocess.run([str(executable), str(output)], cwd=NATIVE, check=True, timeout=90)
    if hashes(sources(False)) != current_sources:
        raise SystemExit("Production sources changed during export; reject these guide assets.")
    manifest = {"schemaVersion": 1, "fixturePrivacy": "Fictional native UI only; local export, no installed-app or personal-data access.",
        "sourceSHA256": current_sources, "exportSourceSHA256": digest(HERE / "ExportGuide.swift"),
        "verifiedModuleReceipt": str(stamp.relative_to(NATIVE)), "moduleOutputs": receipt["outputs"],
        "assetsSHA256": {path.name: digest(path) for path in sorted(output.glob("DABIN__GUIDE__*.png"))}}
    (output / "guide-native-source-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("Source-verified guide assets:", output)


if __name__ == "__main__":
    main()
