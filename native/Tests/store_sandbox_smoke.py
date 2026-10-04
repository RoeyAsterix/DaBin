#!/usr/bin/env python3
"""Build/run an isolated ad-hoc App Sandbox fixture against a verified Store QA module.

No production application, GUI, personal archive, clipboard, network, or permission
panel is involved. This is runtime smoke evidence, not distribution-signing QA.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
MODULE = "DaBinTestCore"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(argv, log, timeout=120):
    with log.open("w") as stream:
        result = subprocess.run([str(arg) for arg in argv], stdout=stream,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"Command exited {result.returncode}; see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-dir", required=True, type=Path)
    parser.add_argument("--output", type=Path, help="New evidence directory; default is a unique /private/tmp directory")
    parser.add_argument("--run", action="store_true", help="Launch the headless fixture twice to test save/reopen/export")
    args = parser.parse_args()
    module_dir = args.module_dir.resolve()
    stamp_path = module_dir / "module-ready.json"
    stamp = json.loads(stamp_path.read_text())
    inputs = stamp["inputs"]
    if inputs.get("distribution") != "app-store" or "DABIN_DIRECT_UPDATES" in inputs.get("compileDefinitions", []):
        raise RuntimeError("The module receipt must explicitly identify the app-store distribution without direct update definitions")
    library = module_dir / f"lib{MODULE}.dylib"
    swiftmodule = module_dir / f"{MODULE}.swiftmodule"
    for path in (library, swiftmodule):
        if stamp["outputs"].get(path.name) != sha(path):
            raise RuntimeError(f"Module output hash differs from its compile receipt: {path.name}")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="dabin-store-sandbox-smoke-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    identifier = "com.dabin.qa.sandbox." + uuid.uuid4().hex
    container = Path.home() / "Library/Containers" / identifier
    if container.exists():
        raise RuntimeError("The unique test container unexpectedly already exists")
    # This workspace directory is outside the new app's bundle, container and
    # temporary-directory allowances; no user-selected grant is requested.
    denial = ROOT / "build" / ("sandbox-denied-" + uuid.uuid4().hex)
    denial.mkdir(parents=True, mode=0o700, exist_ok=False)
    private = denial / "FictionalPrivate.txt"
    private.write_text("Fictional private fixture: violet quartz lantern.\n")
    private.chmod(0o600)
    private_hash = sha(private)
    app = output / "DaBin Store Sandbox Smoke.app"
    binary = app / "Contents/MacOS/DaBinStoreSandboxSmoke"
    frameworks = app / "Contents/Frameworks"
    binary.parent.mkdir(parents=True)
    frameworks.mkdir()
    bundled_library = frameworks / library.name
    shutil.copyfile(library, bundled_library)
    plist = {"CFBundleIdentifier": identifier, "CFBundleName": "DaBin Store Sandbox Smoke",
             "CFBundleExecutable": binary.name, "CFBundlePackageType": "APPL",
             "CFBundleVersion": "1", "CFBundleShortVersionString": "0.0.1",
             "LSUIElement": True, "LSMinimumSystemVersion": "14.0"}
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    entitlements = output / "Smoke.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    source = ROOT / "Tests/StoreSandboxSmokeTests.swift"
    wrapper = output / "StoreSandboxSmokeTests.swift"
    wrapper.write_text(f"@testable import {MODULE}\n" + source.read_text())
    compile_argv = ["xcrun", "swiftc", "-swift-version", "5", "-target", inputs["target"],
                    "-parse-as-library", "-warnings-as-errors", "-I", module_dir,
                    "-L", module_dir, "-l" + MODULE, "-Xlinker", "-rpath", "-Xlinker",
                    "@executable_path/../Frameworks", "-module-cache-path", output / "ModuleCache",
                    wrapper, "-o", binary]
    report = {"schemaVersion": 1, "passed": False, "scope": "isolated ad-hoc sandbox smoke; not distribution-signed application",
              "bundleIdentifier": identifier, "bundle": str(app), "moduleReceipt": str(stamp_path),
              "moduleSHA256": sha(library), "testSHA256": sha(source), "scriptSHA256": sha(Path(__file__)),
              "compileCommand": [str(arg) for arg in compile_argv], "moduleInputs": inputs,
              "syntheticDenialFixture": str(denial), "fixtureMode": "owner read/write file in owner-only directory",
              "launchMethod": "direct headless test executable; no Launch Services or window activation", "phases": []}
    try:
        command(compile_argv, output / "compile.log")
        command(["/usr/bin/codesign", "--force", "--sign", "-", bundled_library], output / "sign-library.log")
        command(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", entitlements, app], output / "sign-app.log")
        command(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], output / "signature-verify.log")
        command(["/usr/bin/codesign", "--display", "--entitlements", ":-", app], output / "signed-entitlements.log")
        report["buildPassed"] = True
        if args.run:
            for phase in ("save", "reopen-export"):
                stdout = output / f"{phase}.stdout.json"
                stderr = output / f"{phase}.stderr.log"
                argv = [str(binary), phase, identifier, str(denial)]
                # No inherited dyld injection or sandbox extension is permitted.
                environment = {key: value for key, value in os.environ.items()
                               if not key.startswith(("DYLD_", "DABIN_")) and key != "APP_SANDBOX_CONTAINER_ID"}
                with stdout.open("w") as out, stderr.open("w") as err:
                    process = subprocess.run(argv, stdout=out, stderr=err, env=environment,
                                             timeout=60, check=False)
                try:
                    receipt = json.loads(stdout.read_text())
                except ValueError:
                    receipt = {"passed": False, "error": "The fixture produced no valid runtime receipt",
                               "stdoutBytes": stdout.stat().st_size}
                report["phases"].append({"phase": phase, "exitCode": process.returncode,
                                         "receipt": receipt, "stderr": str(stderr), "command": argv})
                if process.returncode or receipt.get("passed") is not True:
                    raise RuntimeError(f"Sandbox phase {phase} failed; see {stdout} and {stderr}")
            report["passed"] = True
        else:
            report["runtimeStatus"] = "not_run"
        if sha(private) != private_hash or (denial / "ForbiddenOutput.txt").exists():
            raise RuntimeError("The ungranted external synthetic fixture changed")
        report["externalFixturePreserved"] = True
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["passed"] = False
        report["error"] = str(error)
    finally:
        report["externalFixturePreserved"] = sha(private) == private_hash and not (denial / "ForbiddenOutput.txt").exists()
        # Remove only the files and directory freshly created by this invocation.
        for path in (denial / "ForbiddenOutput.txt", private):
            if path.exists():
                path.unlink()
        denial.rmdir()
        report["externalFixtureRemoved"] = True
        (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(output / "report.json")
    return 0 if report.get("buildPassed") and (not args.run or report["passed"]) else 1


if __name__ == "__main__":
    sys.exit(main())
