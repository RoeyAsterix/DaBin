#!/usr/bin/env python3
"""Record aggregate local archive byte hashes without disclosing file names/content."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
from datetime import datetime, timezone


def snapshot(root):
    entries, total_bytes = [], 0
    if not root.exists():
        return {"root": str(root), "exists": False, "fileCount": 0}
    if root.is_symlink():
        raise RuntimeError("Archive root is a symlink; preserved without following it")
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in sorted(folders + files):
            path = Path(directory) / name
            before = path.lstat()
            if stat.S_ISLNK(before.st_mode):
                value = hashlib.sha256(os.readlink(path).encode()).hexdigest()
                kind = "symlink"
            elif stat.S_ISREG(before.st_mode):
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
                value, kind = digest.hexdigest(), "file"
                total_bytes += before.st_size
                after = path.lstat()
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise RuntimeError("Archive changed during hashing; do not certify preservation")
            elif stat.S_ISDIR(before.st_mode):
                value, kind = "", "directory"
            else:
                raise RuntimeError("Unexpected archive entry type; preserved")
            entries.append([str(path.relative_to(root)), kind, stat.S_IMODE(before.st_mode), before.st_size if kind == "file" else 0, value])
    return {"root": str(root), "exists": True,
            "fileCount": sum(row[1] == "file" for row in entries), "totalBytes": total_bytes,
            "contentAndStructureSHA256": hashlib.sha256(json.dumps(sorted(entries), separators=(",", ":")).encode()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Choose a new receipt path; existing evidence is preserved")
    home = Path.home()
    roots = [home / "Library/Containers/com.dabin.mac/Data/Library/Application Support/DaBin",
             home / "Library/Application Support/DaBin"]
    record = {"recordedUTC": datetime.now(timezone.utc).isoformat(),
              "scope": "Local byte/structure hash only; no file names or contents emitted; symlinks not followed",
              "roots": [snapshot(root) for root in roots]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
