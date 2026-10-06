#!/usr/bin/env python3
"""Read public local certificate/profile facts; never sign or contact Apple."""
import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[3]
NATIVE = REPO / "native"
sys.path.insert(0, str(NATIVE / "scripts"))
from app_store_preflight import provisioning_profile_violations
from project_inventory import build_inventory, fingerprint


def run(arguments, data=None):
    result = subprocess.run(arguments, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
    return result.returncode, result.stdout, result.stderr.decode(errors="replace").strip()


def certificate(der):
    code, output, error = run(["/usr/bin/openssl", "x509", "-inform", "DER", "-noout",
                               "-subject", "-issuer", "-dates", "-serial", "-nameopt", "RFC2253"], der)
    values = {}
    for line in output.decode(errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    ou = re.search(r"(?:^|,)OU=([^,]+)", values.get("subject", ""))
    values.update(SHA1=hashlib.sha1(der).hexdigest().upper(), SHA256=hashlib.sha256(der).hexdigest(),
                  subjectOU=ou.group(1) if ou else None, decodeExitCode=code)
    if error:
        values["decodeStderr"] = error
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    signing = json.loads((NATIVE / "Config/AppStoreSigning.json").read_text())
    team, bundle = signing["developmentTeam"], signing["bundleIdentifier"]
    before = build_inventory()
    identities, queries = {}, []
    for policy in ("codesigning", "basic"):
        command = ["/usr/bin/security", "find-identity", "-v", "-p", policy]
        code, output, error = run(command)
        (args.output / ("identities-" + policy + ".txt")).write_bytes(output)
        found = [{"SHA1": match.group(1), "commonName": match.group(2)}
                 for match in re.finditer(r'\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"', output.decode(errors="replace"))]
        identities[policy] = found
        queries.append({"command": command, "exitCode": code, "stderr": error})
    valid_hashes = {item["SHA1"].upper() for values in identities.values() for item in values}
    certificates = {}
    for common_name in ("Apple Distribution", "Apple Development", "Developer ID Application",
                        "Mac Installer Distribution", "3rd Party Mac Developer Installer",
                        "3rd Party Mac Developer Application", "Mac Developer"):
        command = ["/usr/bin/security", "find-certificate", "-a", "-c", common_name, "-p"]
        code, output, error = run(command)
        queries.append({"command": command, "exitCode": code, "stderr": error})
        for block in re.findall(rb"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----", output, re.S):
            decoded = certificate(base64.b64decode(block))
            decoded["validIdentityListed"] = decoded["SHA1"] in valid_hashes
            certificates[decoded["SHA1"]] = decoded
    roots = [Path.home() / "Library/MobileDevice/Provisioning Profiles",
             Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]
    profiles, profile_search, decode_errors, unmatched = [], [], [], 0
    now = datetime.datetime.now(datetime.timezone.utc)
    for root in roots:
        paths = sorted({*root.glob("*.provisionprofile"), *root.glob("*.mobileprovision")})
        profile_search.append({"root": str(root), "exists": root.is_dir(), "profileFiles": len(paths)})
        for path in paths:
            code, output, error = run(["/usr/bin/security", "cms", "-D", "-i", str(path)])
            if code:
                decode_errors.append({"path": str(path), "exitCode": code, "stderr": error})
                continue
            try:
                profile = plistlib.loads(output)
            except (ValueError, plistlib.InvalidFileException):
                decode_errors.append({"path": str(path), "error": "Decoded profile was not a plist"})
                continue
            claims = profile.get("Entitlements", {})
            app_id = claims.get("com.apple.application-identifier", claims.get("application-identifier", ""))
            if team not in profile.get("TeamIdentifier", []) and not str(app_id).endswith("." + bundle):
                unmatched += 1
                continue
            allowed = []
            for data in profile.get("DeveloperCertificates", []):
                value = certificate(data)
                value["validIdentityListed"] = value["SHA1"] in valid_hashes
                value["installedPublicCertificateFound"] = value["SHA1"] in certificates
                allowed.append(value)
            expiry = profile.get("ExpirationDate")
            if isinstance(expiry, datetime.datetime) and expiry.tzinfo is None:
                expiry = expiry.replace(tzinfo=datetime.timezone.utc)
            profiles.append({
                "path": str(path), "fileSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "uuid": profile.get("UUID"), "name": profile.get("Name"),
                "teamIdentifiers": profile.get("TeamIdentifier", []), "platforms": profile.get("Platform", []),
                "applicationIdentifierPrefix": profile.get("ApplicationIdentifierPrefix", []),
                "applicationIdentifier": app_id, "entitlementTeam": claims.get("com.apple.developer.team-identifier"),
                "expirationUTC": expiry.isoformat() if isinstance(expiry, datetime.datetime) else None,
                "expired": not isinstance(expiry, datetime.datetime) or expiry <= now,
                "deviceCount": len(profile.get("ProvisionedDevices", [])),
                "provisionsAllDevices": profile.get("ProvisionsAllDevices", False),
                "getTaskAllow": claims.get("com.apple.security.get-task-allow", claims.get("get-task-allow")),
                "capabilityClaims": {key: value for key, value in claims.items() if key.startswith("com.apple.security.")},
                "storeProfileViolations": provisioning_profile_violations(profile, team, bundle, now),
                "allowedPublicCertificates": allowed,
            })
    after = build_inventory()
    result = {
        "checkedAtUTC": now.isoformat(), "team": team, "bundleIdentifier": bundle,
        "productionFingerprintBefore": fingerprint(before), "productionFingerprintAfter": fingerprint(after),
        "productionInputsUnchanged": before == after, "identities": identities,
        "publicCertificates": list(certificates.values()), "profileSearch": profile_search,
        "profilesForTargetTeamOrBundle": profiles, "unrelatedProfilesOmitted": unmatched,
        "profileDecodeErrors": decode_errors, "queries": queries,
        "boundary": "Read-only installed signing identity listings, public certificate metadata, and locally installed provisioning profiles in the two standard directories. No private-key export/use, signing, Keychain mutation, GUI, network, Apple account action, profile download or source mutation. Identity availability does not prove protected private-key access during signing.",
    }
    (args.output / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
