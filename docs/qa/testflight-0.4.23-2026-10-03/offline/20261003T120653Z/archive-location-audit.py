"""Disposable, offline archive-path policy probe; never creates an archive."""

import json
from pathlib import Path
import sys
import tempfile
from unittest import mock


REPOSITORY = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPOSITORY / "native/scripts"))
import app_store_archive_location as location


with tempfile.TemporaryDirectory(prefix="DaBinArchivePathAudit-", dir="/private/tmp") as temporary:
    root = Path(temporary).resolve()
    project = root / "project"
    project.mkdir()
    safe = root / "archives" / "DaBin.xcarchive"
    traversal = root / "not-created" / ".." / "project" / "DaBin.xcarchive"
    with mock.patch.object(location, "file_provider_attribute", return_value=None):
        safe_accepted = location.validate(safe, project) == safe
        try:
            accepted = location.validate(traversal, project)
        except ValueError:
            traversal_refused = True
            resolves_into_project = False
        else:
            traversal_refused = False
            resolves_into_project = accepted.resolve(strict=False).is_relative_to(project)
    report = {
        "status": "PASS" if safe_accepted and traversal_refused else "FAIL",
        "ordinaryExternalDestinationAccepted": safe_accepted,
        "parentTraversalDestinationRefused": traversal_refused,
        "acceptedTraversalResolvesIntoProject": resolves_into_project,
        "fixtureCreatedArchive": False,
        "fileProviderAttributeProbe": "mocked; this checks path containment only",
        "finding": "A destination through a nonexistent component followed by '..' can resolve into the forbidden source repository unless traversal is rejected or the complete destination is normalized before containment checks.",
    }
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["status"] == "PASS" else 1)
