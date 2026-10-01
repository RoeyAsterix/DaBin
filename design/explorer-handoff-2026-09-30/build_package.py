#!/usr/bin/env python3
"""Package only the reviewed feature handoff; never read the user's archive."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parents[1]
DESTINATION = ROOT / "DaBin-Explorer-Open-Design-Handoff.zip"
PREFIX = "DaBin-Explorer-Open-Design-Handoff"
ROOT_FILES = {
    "README.md", "BRIEF.md", "INTERACTIONS.md", "ACCEPTANCE.md",
    "OPEN_DESIGN_PROMPT.txt", "IMPLEMENTATION_STATUS.md", "SOURCE_MAP.md", "REFERENCE_PROVENANCE.json",
    "NATIVE_BUILD_NOTES.md", "build_package.py", "build_wireframes.py",
}

def snapshot_native():
    native = REPOSITORY / "native"
    sources = sorted(native.glob("Sources/DaBin/*.swift"))
    if not sources:
        raise SystemExit("Package creation requires the original DaBin repository.")
    tracked = subprocess.check_output(["git", "ls-files", "-z", "native/Resources"],
                                      cwd=REPOSITORY).decode().split("\0")
    inputs = sources + [REPOSITORY / path for path in tracked if path]
    inputs += [native / path for path in ("UpdateTools/DaBinUpdater.swift", "scripts/build.sh",
                                         "scripts/build_app.py", "scripts/project_inventory.py")]
    records = []
    for path in sorted(set(inputs)):
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(native.resolve()):
            raise SystemExit(f"Unsafe source input: {path}")
        relative = path.relative_to(REPOSITORY)
        data = path.read_bytes()
        destination = ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.is_symlink() or not destination.parent.resolve().is_relative_to(ROOT):
            raise SystemExit(f"Unsafe snapshot output: {destination}")
        destination.write_bytes(data)
        shutil.copymode(path, destination)
        records.append({"file": str(relative), "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
    for record in records:
        if hashlib.sha256((REPOSITORY / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
            raise SystemExit("Source changed during snapshot. Package after edits finish.")
    info = plistlib.loads((ROOT / "native/Resources/Info.plist").read_bytes())
    manifest = {"created_at": datetime.now(timezone.utc).isoformat(),
                "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                "source": "Current working tree, including uncommitted Explorer implementation",
                "runtime_swift_file_count": len(sources),
                "scope": "Runtime source and standalone local build inputs; no test/upload/installer pipeline",
                "files": records}
    (ROOT / "SOURCE_SNAPSHOT.json").write_text(json.dumps(manifest, indent=2)+"\n")
    return [ROOT / record["file"] for record in records] + [ROOT / "SOURCE_SNAPSHOT.json"]

def main():
    status = (ROOT / "IMPLEMENTATION_STATUS.md").read_text()
    if "Release verification pending" in status or "will be finalized" in status:
        raise SystemExit("Finalize implementation status before packaging.")
    paths = sorted(ROOT / name for name in ROOT_FILES)
    paths += snapshot_native()
    for directory in ("reference", "wireframes"):
        paths.extend(sorted((ROOT / directory).rglob("*")))
    paths = [p for p in paths if p.is_file()]
    for path in paths:
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT):
            raise SystemExit(f"Unsafe input: {path}")
    records = [{"file": str(p.relative_to(ROOT)), "bytes": p.stat().st_size,
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
    manifest = {"created_at": datetime.now(timezone.utc).isoformat(),
                "package_type": "Design handoff, not an installer",
                "private_capture_content_included": False, "files": records}
    with zipfile.ZipFile(DESTINATION, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in paths:
            archive.write(path, f"{PREFIX}/{path.relative_to(ROOT)}")
        archive.writestr(f"{PREFIX}/MANIFEST.json", json.dumps(manifest, indent=2)+"\n")
    with zipfile.ZipFile(DESTINATION) as archive:
        assert archive.testzip() is None
        for record in records:
            data = archive.read(f"{PREFIX}/{record['file']}")
            assert hashlib.sha256(data).hexdigest() == record["sha256"]
        assert all(not name.startswith("/") and ".." not in Path(name).parts
                   for name in archive.namelist())
    snapshot = json.loads((ROOT / "SOURCE_SNAPSHOT.json").read_text())
    for record in snapshot["files"]:
        if hashlib.sha256((REPOSITORY / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
            raise SystemExit("Source changed during packaging; do not distribute this ZIP. Rebuild it after edits finish.")
    receipt = {"file": DESTINATION.name, "files": len(records)+1,
               "bytes": DESTINATION.stat().st_size,
               "sha256": hashlib.sha256(DESTINATION.read_bytes()).hexdigest(),
               "crc_and_hash_verification": "PASS"}
    (ROOT / "PACKAGE_VERIFICATION.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps(receipt, indent=2))

if __name__ == "__main__":
    main()
