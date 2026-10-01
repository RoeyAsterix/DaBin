#!/usr/bin/env python3
"""Validate that an App Store archive destination is outside synced source trees."""

import argparse
from pathlib import Path
import subprocess


FILE_PROVIDER_ATTRIBUTES = {
    "com.apple.file-provider-domain-id",
    "com.apple.fileprovider.fpfs#P",
}


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def existing_ancestors(path: Path):
    current = path
    while not current.exists() and current != current.parent:
        current = current.parent
    while True:
        yield current
        if current == current.parent:
            break
        current = current.parent


def file_provider_attribute(path: Path) -> str | None:
    try:
        result = subprocess.run(
            ["/usr/bin/xattr", str(path)],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None
    names = result.stdout.splitlines() if result.returncode == 0 else []
    return next(
        (
            name
            for name in names
            if name in FILE_PROVIDER_ATTRIBUTES
            or name.startswith("com.apple.fileprovider.")
        ),
        None,
    )


def validate(destination: Path, project_root: Path) -> Path:
    destination = destination.expanduser().absolute()
    project_root = project_root.expanduser().resolve(strict=True)
    if destination.suffix != ".xcarchive":
        raise ValueError("The App Store archive path must end in .xcarchive")
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"The archive destination already exists: {destination}")

    parent = destination.parent
    nearest_existing = next(existing_ancestors(parent))
    if nearest_existing.is_symlink():
        raise ValueError(f"The archive destination uses a symbolic-link parent: {nearest_existing}")
    resolved_parent = nearest_existing.resolve(strict=True)
    if is_within(resolved_parent, project_root):
        raise ValueError("The App Store archive must be outside the source repository")

    for ancestor in existing_ancestors(parent):
        if ancestor.is_symlink():
            raise ValueError(f"The archive destination uses a symbolic-link ancestor: {ancestor}")
        attribute = file_provider_attribute(ancestor)
        if attribute:
            raise ValueError(
                f"The archive destination is managed by File Provider ({attribute} on {ancestor})"
            )
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        destination = validate(args.destination, args.project_root)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Unsafe App Store archive destination: {error}")
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
