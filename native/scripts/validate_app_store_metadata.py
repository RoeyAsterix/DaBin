#!/usr/bin/env python3
"""Validate local listing-copy constraints, not Apple approval or live URL content."""
import argparse
import json
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT.parent / "docs/app-store/metadata-en-US.json"


def validate(path, require_complete=False):
    metadata = json.loads(path.read_text(encoding="utf-8"))
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    page = metadata["productPage"]
    review = metadata["review"]
    errors = []
    checks = []

    def check(condition, message):
        checks.append({"result": "PASS" if condition else "FAIL", "check": message})
        if not condition:
            errors.append(message)

    for field, maximum in [("name", 30), ("subtitle", 30), ("promotionalText", 170), ("description", 4000)]:
        value = page.get(field)
        check(isinstance(value, str) and 0 < len(value) <= maximum,
              f"{field} contains 1-{maximum} characters")
    keywords = page.get("keywords", "")
    check(isinstance(keywords, str) and 0 < len(keywords.encode("utf-8")) <= 100,
          "keywords fit Apple's 100-byte limit")
    check(all(len(word.strip()) > 2 for word in keywords.split(",")),
          "each keyword is longer than two characters")
    check(0 < len(review.get("notes", "").encode("utf-8")) <= 4000,
          "review notes fit Apple's 4000-byte limit")
    check(review.get("signInRequired") is False,
          "draft matches the no-account implementation")
    for field, info_key in [("bundleIdentifier", "CFBundleIdentifier"), ("version", "CFBundleShortVersionString"), ("build", "CFBundleVersion")]:
        check(metadata["candidate"].get(field) == info.get(info_key),
              f"candidate {field} matches source Info.plist")
    check(page.get("privacyPolicyURL") == info.get("DaBinPrivacyPolicyURL"),
          "draft privacy URL matches source bundle configuration")
    check("<" not in page.get("description", "") and ">" not in page.get("description", ""),
          "description is plain text, without HTML")
    pending = list(metadata.get("pendingGates", []))
    if require_complete:
        for field in ["supportURL", "copyright"]:
            check(bool(page.get(field)), f"owner confirmed {field}")
        for field in ["contactName", "contactEmail", "contactPhone"]:
            check(bool(review.get(field)), f"owner confirmed review {field}")
        for field, value in metadata.get("ownerDecisions", {}).items():
            check(value is not None, f"owner confirmed {field}")
        check(not pending, "all externally verified submission gates are resolved")
    return {"status": "FAIL" if errors else "LOCAL_DRAFT_CHECKS_PASS",
            "submissionReady": False,
            "checks": checks, "errors": errors, "pendingGates": pending,
            "limits": {"descriptionCharacters": len(page["description"]),
                       "promotionalTextCharacters": len(page["promotionalText"]),
                       "keywordBytes": len(keywords.encode("utf-8")),
                       "reviewNoteBytes": len(review["notes"].encode("utf-8"))},
            "boundary": "This offline check does not verify Apple approval, declarations, signing, screenshots, public URLs or owner identity."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, default=DEFAULT)
    parser.add_argument("--require-complete", action="store_true",
                        help="Also reject unresolved owner fields and external submission gates")
    args = parser.parse_args()
    result = validate(args.metadata, args.require_complete)
    print(json.dumps(result, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
