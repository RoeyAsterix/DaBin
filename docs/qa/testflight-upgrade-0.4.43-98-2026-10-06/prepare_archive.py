#!/usr/bin/env python3
"""Archive the exact tested build with installed signing assets; never upload."""
import datetime
import hashlib
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys


def main():
    campaign = Path(__file__).resolve().parent
    native = campaign.parents[2] / "native"
    sys.path.insert(0, str(native / "scripts"))
    from project_inventory import build_inventory, fingerprint

    frozen = json.loads((campaign / "source-freeze.json").read_text())
    current = build_inventory()
    if current != frozen["inputs"] or fingerprint(current) != frozen["productionFingerprint"]:
        raise SystemExit("Tested inputs changed; no archive attempted")
    validation = json.loads((campaign / "validation-summary.json").read_text())
    if not validation.get("approvedForInternalArchive") or validation.get("sourceFingerprint") != frozen["productionFingerprint"]:
        raise SystemExit("Final validation is incomplete or differs from source freeze; no archive attempted")
    configuration = json.loads((campaign / "archive-configuration-freeze.json").read_text())
    for relative, expected in configuration["files"].items():
        if hashlib.sha256((native / relative).read_bytes()).hexdigest() != expected:
            raise SystemExit("Frozen signing configuration/project/scheme changed; no archive attempted")
    info = plistlib.loads((native / "Resources/Info.plist").read_bytes())
    if (info["CFBundleShortVersionString"], str(info["CFBundleVersion"]), info["CFBundleIdentifier"]) != ("0.4.43", "98", "com.dabin.mac"):
        raise SystemExit("Candidate identity differs; no archive attempted")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    archive = Path.home() / "Library/Developer/Xcode/Archives" / day / f"DaBin-0.4.43-98-TestFlight-{stamp}.xcarchive"
    log = campaign / f"archive-{stamp}.log"
    receipt = campaign / f"archive-{stamp}-receipt.json"
    record = {"startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "sourceFingerprint": frozen["productionFingerprint"], "version": "0.4.43", "build": "98",
              "archive": str(archive), "log": str(log), "status": "running",
              "runnerPID": os.getpid(), "uploaded": False,
              "scope": "Existing archive helper and installed signing identities only; no provisioning downloads, authentication control or upload."}
    receipt.write_text(json.dumps(record, indent=2) + "\n")
    environment = os.environ.copy()
    environment["DABIN_APP_STORE_ARCHIVE_PATH"] = str(archive)
    environment["DABIN_DEVELOPMENT_TEAM"] = configuration["developmentTeam"]
    print("Preparing " + str(archive), flush=True)
    with log.open("xb") as stream:
        process = subprocess.Popen([str(native / "scripts/archive_app_store.sh")], cwd=native,
                                   env=environment, stdout=stream, stderr=subprocess.STDOUT)
        record["archiveHelperPID"] = process.pid
        receipt.write_text(json.dumps(record, indent=2) + "\n")
        try:
            code = process.wait()
        except KeyboardInterrupt:
            process.terminate()
            try:
                code = process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                code = process.wait()
            record["interrupted"] = True
    unchanged = build_inventory() == current
    configuration_unchanged = all(hashlib.sha256((native / relative).read_bytes()).hexdigest() == expected
                                  for relative, expected in configuration["files"].items())
    archive_identity_matches = False
    if code == 0:
        try:
            archived = plistlib.loads((archive / "Products/Applications/DaBin.app/Contents/Info.plist").read_bytes())
            archive_identity_matches = (archived.get("CFBundleShortVersionString"), str(archived.get("CFBundleVersion")),
                                        archived.get("CFBundleIdentifier"), archived.get("DaBinSourceFingerprint")) == (
                                        "0.4.43", "98", "com.dabin.mac", frozen["productionFingerprint"])
        except (OSError, ValueError):
            archive_identity_matches = False
    invalidated = code == 0 and not (unchanged and configuration_unchanged and archive_identity_matches)
    if invalidated:
        code = 75
    record.update({"finishedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   "exitCode": code, "status": "invalidated_by_input_or_archive_identity_change" if invalidated else
                   ("archive_preflight_passed" if code == 0 else "archive_incomplete"),
                   "inputsUnchanged": unchanged, "configurationUnchanged": configuration_unchanged,
                   "archiveIdentityMatchesFrozenInputs": archive_identity_matches,
                   "logSHA256": hashlib.sha256(log.read_bytes()).hexdigest()})
    receipt.write_text(json.dumps(record, indent=2) + "\n")
    print(str(receipt), flush=True)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
