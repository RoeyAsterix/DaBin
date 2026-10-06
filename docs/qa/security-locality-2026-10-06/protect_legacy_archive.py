#!/usr/bin/env python3
"""Restrict only the known, owner-controlled legacy DaBin archive root."""
import datetime
import json
import os
from pathlib import Path
import stat


def main():
    root = Path.home() / "Library/Application Support/DaBin"
    receipt = Path(__file__).with_name("legacy-root-permission-receipt.json")
    if receipt.exists():
        raise SystemExit("Existing evidence preserved; no permission change attempted")
    before = root.lstat()
    if not stat.S_ISDIR(before.st_mode) or before.st_uid != os.geteuid():
        raise SystemExit("Expected an owner-controlled real directory; preserved")
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        opened = os.fstat(fd)
        if (opened.st_dev, opened.st_ino, opened.st_uid) != (before.st_dev, before.st_ino, os.geteuid()):
            raise SystemExit("Archive root changed; preserved")
        os.fchmod(fd, 0o700)
        after = os.fstat(fd)
        current = root.lstat()
        if (current.st_dev, current.st_ino) != (after.st_dev, after.st_ino):
            raise SystemExit("Root pathname changed; original owned directory alone was protected")
        if stat.S_IMODE(after.st_mode) != 0o700:
            raise SystemExit("Private directory mode was not applied")
    finally:
        os.close(fd)
    receipt.write_text(json.dumps({
        "recordedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "path": str(root),
        "beforeMode": oct(stat.S_IMODE(before.st_mode)),
        "afterMode": "0o700",
        "sameDeviceAndInode": True,
        "scope": "Only the existing inactive legacy archive root mode changed; no child content was read, moved or rewritten.",
    }, indent=2) + "\n")
    print("Legacy DaBin archive root verified private (0700); contents preserved")


if __name__ == "__main__":
    main()
