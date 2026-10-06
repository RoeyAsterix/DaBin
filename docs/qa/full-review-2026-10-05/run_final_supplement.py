#!/usr/bin/env python3
"""Run the final local QA supplements sequentially against a finished Store report.

Without --run, verify inputs and print the plan only. Native execution requires
the coordinator to have released the final frozen GUI stage. This helper never
archives, uses developer signing identities, exports, uploads, accesses accounts
or installs the app. The sandbox fixture alone receives an ad-hoc signature.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
NATIVE = HERE.parents[2] / "native"
FREEZE = HERE / "final-candidate/source-freeze.json"
FINAL_FINGERPRINT = "d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa"
PROFILE = HERE / "profile_workspace_zoom.py"
PRIVACY = HERE / "privacy-render-supplement/run_privacy_render.py"
XCTEST_NAMES = {
    "testStoredOriginalAndDaySurviveReopen",
    "testSearchIncludesOnlySameDayNeighborsAcrossTypeFilter",
}
STAGES = ["sustained-600s", "unsigned-store-build", "release-xctest",
          "enforced-sandbox-smoke", "privacy-render"]


def utc():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object: {path}")
    return value


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def new_output(path):
    path = path.expanduser().absolute()
    require(".." not in path.parts and path != HERE and path.is_relative_to(HERE),
            "Output must be a new child of this QA evidence directory")
    require(not path.exists(), "Output already exists; choose a new directory")
    require(not any(p.is_symlink() for p in (path, *path.parents)),
            "Output may not have a symbolic-link ancestor")
    return path


def verify_inputs(report_path):
    report_path = report_path.resolve()
    runs = NATIVE / "build/qa/runs"
    require(report_path.name == "report.json" and report_path.parent.parent == runs
            and report_path.parent.name.endswith("-app-store"),
            "Select an actual immutable native full Store run report, not latest-run or a copied summary")
    freeze = read_json(FREEZE)
    require(freeze.get("productionFingerprint") == FINAL_FINGERPRINT
            and (freeze.get("version"), freeze.get("build")) == ("0.4.41", "96"),
            "The selected final source freeze is not the reviewed 0.4.41 (96) candidate")
    for relative, expected in freeze["inputs"].items():
        require(sha(NATIVE / relative) == expected, f"Frozen production input changed: {relative}")
    inventory = load_module("final_supplement_inventory", NATIVE / "scripts/project_inventory.py")
    require(inventory.build_inventory() == freeze["inputs"]
            and inventory.fingerprint(freeze["inputs"]) == FINAL_FINGERPRINT,
            "Current production inventory differs from the final source freeze")
    tests = inventory.hashes(list((NATIVE / "Tests").glob("*.swift")))
    require(tests == freeze["testSHA256"], "Current Swift test inventory differs from the final freeze")
    sys.path.insert(0, str(NATIVE / "scripts"))
    qa = load_module("final_supplement_qa_inventory", NATIVE / "scripts/run_qa.py")
    names = list(dict.fromkeys(qa.NONFOCUS + qa.WINDOW))
    require(len(names) == 126, "Expected the reviewed 126 registered native suites")
    report = read_json(report_path)
    require(report.get("configuration") == "Release" and report.get("distribution") == "app-store"
            and report.get("compileDefinitions") == []
            and report.get("coverage") == "full_registered_suite"
            and report.get("sourceChangedDuringRun") is False,
            "A source-unchanged full Store Release campaign is required")
    started = datetime.fromisoformat(report["startedAtUTC"])
    finished = datetime.fromisoformat(report["finishedAtUTC"])
    require(started.tzinfo is not None and finished.tzinfo is not None and finished >= started,
            "The full campaign must have a valid finished UTC interval")
    require(report.get("productionModule", {}).get("status") == "passed",
            "The campaign production module did not compile successfully")
    require(report.get("inputs") == qa.input_snapshot(names)
            and report.get("sourceFingerprint") == inventory.fingerprint(report["inputs"]),
            "Full QA input manifest no longer matches its current source, tests and resources")
    suites = report.get("suites", [])
    require(len(suites) == 126 and len({s["name"] for s in suites}) == 126
            and {s["name"] for s in suites} == set(names),
            "All 126 suites must be requested exactly once")
    failed = []
    logs = {}
    for suite in suites:
        require(suite.get("status") in {"passed", "failed"}
                and suite.get("compile", {}).get("status") == "passed",
                f"Campaign contains an incomplete, blocked or compile-failed suite: {suite['name']}")
        log = (NATIVE / suite["log"]).resolve()
        require(log.parent == report_path.parent and log.is_file(),
                f"Suite log is missing or outside its actual run: {suite['name']}")
        logs[str(log)] = sha(log)
        if suite["status"] == "passed":
            require(suite.get("exitCode") == 0, f"PASS suite has a nonzero exit: {suite['name']}")
        else:
            failed.append(suite["name"])
            text = log.read_text(errors="replace")
            require(suite["name"] == "WorkspaceZoomPerformanceTests" and suite.get("exitCode") == 1
                    and "CYCLE: 5/5" in text and "STAGES:" in text
                    and re.search(r"Workspace zoom performance QA failed:.*(?:50|33) ms budget", text),
                    "Only a completed original zoom budget failure may remain in the full baseline")
    require(report.get("passedSuites") == 126 - len(failed)
            and report.get("failedSuites") == len(failed)
            and report.get("status") == ("failed" if failed else "passed"),
            "Campaign totals/status disagree with its actual suite results")
    profile = load_module("final_supplement_profile", PROFILE)
    module_path, module = profile.select_module(argparse.Namespace(module_receipt=None, run_report=report_path))
    profile.verify_test(module_path, module)
    require(module["inputs"]["distribution"] == "app-store"
            and set(module["outputs"]) == {"libDaBinTestCore.dylib", "DaBinTestCore.swiftmodule"},
            "The report must resolve the exact Store module outputs")
    info = plistlib.loads((NATIVE / "Resources/Info.plist").read_bytes())
    require((info["CFBundleShortVersionString"], info["CFBundleVersion"]) == ("0.4.41", "96"),
            "Current application version/build differs from the final freeze")
    require(set(re.findall(r"func (test\w+)\(", (NATIVE / "Tests/XcodeSmokeTests.swift").read_text()))
            == XCTEST_NAMES, "The separate XCTest source must contain exactly the two reviewed cases")
    paths = {NATIVE / p for p in freeze["inputs"]} | {NATIVE / p for p in tests}
    paths |= {NATIVE / p for p in report["inputs"]}
    paths |= {NATIVE / "Config/AppStoreSigning.json", NATIVE / "DaBin.xcodeproj/project.pbxproj",
              NATIVE / "DaBin.xcodeproj/xcshareddata/xcschemes/DaBin.xcscheme",
              NATIVE / "Tests/store_sandbox_smoke.py", PROFILE, PRIVACY, Path(__file__), FREEZE,
              report_path, module_path}
    paths |= {module_path.parent / name for name in module["outputs"]}
    paths |= {Path(p) for p in logs}
    snapshot = {str(p.resolve()): sha(p) for p in sorted(paths)}
    return {"reportPath": report_path, "report": report, "freeze": freeze, "inventory": inventory,
            "snapshot": snapshot, "modulePath": module_path, "module": module, "profile": profile,
            "baselineFailedSuites": failed, "version": "0.4.41", "build": "96"}


def unchanged(inputs):
    require(inputs["inventory"].build_inventory() == inputs["freeze"]["inputs"],
            "Production input inventory changed during the supplement")
    tests = inputs["inventory"].hashes(list((NATIVE / "Tests").glob("*.swift")))
    require(tests == inputs["freeze"]["testSHA256"], "Swift test inventory changed during the supplement")
    for path, expected in inputs["snapshot"].items():
        require(sha(path) == expected, f"Supplement input or exact module output changed: {path}")


def save_report(path, report):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def run_logged(command, log, timeout):
    started = time.monotonic()
    entry = {"command": [str(arg) for arg in command], "workingDirectory": str(NATIVE),
             "startedUTC": utc(), "log": str(log), "timeoutSeconds": timeout,
             "status": "failed", "exitCode": None}
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("DABIN_", "DYLD_"))
                   and k not in {"APP_SANDBOX_CONTAINER_ID", "XCTestConfigurationFilePath"}}
    with log.open("w") as stream:
        try:
            process = subprocess.Popen(entry["command"], cwd=NATIVE, env=environment,
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            entry["ownedPID"] = process.pid
            try:
                entry["exitCode"] = process.wait(timeout=timeout)
                entry["status"] = "passed" if entry["exitCode"] == 0 else "failed"
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                entry["status"] = "timed_out_or_interrupted"
                entry["outerTimedOutOrInterrupted"] = True
                # Signal only the process group created by this invocation.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    entry["exitCode"] = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    entry["exitCode"] = process.wait(timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            entry["error"] = str(error)
            stream.write(str(error) + "\n")
    entry.update({"finishedUTC": utc(), "seconds": round(time.monotonic() - started, 3),
                  "logSHA256": sha(log)})
    return entry


def record_receipt(phase, path):
    receipt = read_json(path)
    phase.update({"receipt": str(path), "receiptSHA256": sha(path), "result": receipt})
    if (receipt.get("sourceChangedDuringRun") is True or receipt.get("inputsUnchanged") is False
            or receipt.get("sourceAndModuleUnchanged") is False
            or "INVALIDATED_BY_INPUT_CHANGES" in receipt.get("status", "").upper()):
        phase.update({"inputChangeObserved": True, "sourceAndModuleUnchanged": False,
                      "status": "invalidated_by_input_changes"})
    return receipt


def bundle_executable(bundle):
    info_path = bundle / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    name = info.get("CFBundleExecutable")
    require(isinstance(name, str) and name and Path(name).name == name,
            f"Bundle has no valid CFBundleExecutable: {bundle}")
    executable = bundle / "Contents/MacOS" / name
    require(executable.is_file(), f"Bundle executable is missing: {executable}")
    return executable, info_path


def xctest_evidence(phase, temporary, output):
    source = temporary / "DaBinSmoke.xcresult"
    require(source.is_dir(), "XCTest did not produce a result bundle")
    result = output / "DaBinSmoke.xcresult"
    shutil.copytree(source, result)
    phase.update({"temporaryResultBundle": str(source), "preservedResultBundle": str(result),
                  "resultBundleSHA256": {str(p.relative_to(result)): sha(p)
                                         for p in sorted(result.rglob("*")) if p.is_file()},
                  "derivedData": str(temporary / "derived-data"),
                  "testSourceSHA256": sha(NATIVE / "Tests/XcodeSmokeTests.swift"),
                  "testHostLaunchGuardSHA256": sha(NATIVE / "Sources/DaBin/AppDelegate.swift")})
    lines = Path(phase["log"]).read_text(errors="replace").splitlines()
    observations = {}
    for line in lines:
        if "test case" in line.lower():
            for name in re.findall(r"\btest\w+", line):
                observations.setdefault(name, []).append(line)
    phase["testCaseLogObservations"] = observations
    phase["testCaseResults"] = {name: "passed" if any(re.search(r"\bpassed\b", line)
                                     for line in observations.get(name, [])) else "unverified"
                                for name in sorted(XCTEST_NAMES)}
    phase["testResultScope"] = "Exact native XCTest case/pass log lines plus preserved original xcresult bundle"
    require(set(observations) == XCTEST_NAMES
            and all(value == "passed" for value in phase["testCaseResults"].values())
            and any(re.search(r"Executed 2 tests, with 0 failures", line) for line in lines),
            "The log does not verify exactly the two requested XCTest cases with zero failures")
    products = temporary / "derived-data/Build/Products/Release"
    host_bundle = products / "DaBin.app"
    host, host_info = bundle_executable(host_bundle)
    candidates = [host_bundle / "Contents/PlugIns/DaBinTests.xctest", products / "DaBinTests.xctest"]
    bundles = [path for path in candidates if path.is_dir()]
    require(len(bundles) == 1, "Expected exactly one embedded or standalone DaBinTests XCTest bundle")
    test_binary, test_info = bundle_executable(bundles[0])
    phase.update({"testHostExecutable": str(host), "testHostInfoSHA256": sha(host_info),
                  "testBundle": str(bundles[0]), "testBundleExecutable": str(test_binary),
                  "testBundleInfoSHA256": sha(test_info)})
    phase["testHostSHA256"] = sha(host)
    phase["testBundleExecutableSHA256"] = sha(test_binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run-report", required=True, type=Path, help="Finished native/build/qa/runs/*-app-store/report.json")
    parser.add_argument("--output", type=Path, help="New directory beneath this QA package")
    parser.add_argument("--run", action="store_true", help="Execute only after the coordinator releases all native GUI/build stages")
    args = parser.parse_args()
    try:
        inputs = verify_inputs(args.run_report)
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + uuid.uuid4().hex[:8]
    try:
        output = new_output(args.output or HERE / ("final-supplement-" + run_id))
    except ValueError as error:
        parser.error(str(error))
    candidate = NATIVE / "build" / ("store-unsigned-final-supplement-" + run_id)
    common = {"schemaVersion": 1, "startedUTC": utc(), "sourceFreeze": str(FREEZE),
              "productionFingerprint": FINAL_FINGERPRINT, "version": inputs["version"], "build": inputs["build"],
              "fullStoreReport": str(inputs["reportPath"]), "fullStoreReportSHA256": sha(inputs["reportPath"]),
              "baselineStatus": inputs["report"]["status"], "baselineFailedSuites": inputs["baselineFailedSuites"],
              "moduleReceipt": str(inputs["modulePath"]), "moduleReceiptSHA256": sha(inputs["modulePath"]),
              "moduleOutputs": inputs["module"]["outputs"], "inputs": inputs["snapshot"],
              "stageOrder": STAGES, "submissionReady": False, "archiveCreated": False,
              "uploaded": False, "developerSigningIdentitiesUsed": False,
              "fixturePrivacy": "Fictional UUID archives; no personal archive, general clipboard, network, accounts or permission requests",
              "visualReview": "Privacy render command success does not replace original-resolution image review",
              "sourceCheckScope": "Before and after each sequential phase; no polling profiler competes with the unsampled workload",
              "unsignedCandidateDirectory": str(candidate)}
    if not args.run:
        print(json.dumps({**common, "status": "INPUTS_VERIFIED_NO_NATIVE_EXECUTION", "plannedOutput": str(output)}, indent=2))
        return 0
    output.mkdir(parents=True, exist_ok=False)
    report_path = output / "report.json"
    report = {**common, "status": "running", "phases": [], "sourceAndModuleUnchanged": True}
    save_report(report_path, report)
    # This lock coordinates invocations of this helper. Root coordinates other
    # native runners; a finished campaign alone does not release their GUI stage.
    with (HERE / ".final-supplement.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            report.update({"status": "failed", "error": "Another final supplement owns the sequential stage", "finishedUTC": utc()})
            save_report(report_path, report)
            return 1
        executable = None
        abort = None
        try:
            for field, command in [("compiler", ["xcrun", "swiftc", "--version"]),
                                   ("sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-version"])]:
                unchanged(inputs)
                tool = run_logged(command, output / ("toolchain-" + field + ".log"), 30)
                report.setdefault("toolchainVerification", []).append(tool)
                require(tool["status"] == "passed"
                        and Path(tool["log"]).read_text().strip() == inputs["module"]["inputs"][field],
                        "Current compiler/SDK differs from the finished exact Store module")
            for name in STAGES:
                unchanged(inputs)
                temporary = None
                if name == "sustained-600s":
                    command = [sys.executable, PROFILE, "--run-report", inputs["reportPath"],
                               "--mode", "sustained", "--timeout", "900", "--output", output / "sustained"]
                    timeout = 950
                elif name == "unsigned-store-build":
                    command = [sys.executable, NATIVE / "scripts/build_store_candidate.py", "--output-directory", candidate]
                    timeout = 900
                elif name == "release-xctest":
                    temporary = Path(tempfile.mkdtemp(prefix="DaBin-Final-XCTest-", dir="/private/tmp"))
                    command = ["xcrun", "xcodebuild", "-project", NATIVE / "DaBin.xcodeproj", "-scheme", "DaBin",
                               "-configuration", "Release", "-destination", "platform=macOS,arch=arm64",
                               "-derivedDataPath", temporary / "derived-data", "-resultBundlePath", temporary / "DaBinSmoke.xcresult",
                               "-disableAutomaticPackageResolution", "-parallel-testing-enabled", "NO",
                               *["-only-testing:DaBinTests/DaBinTests/" + test for test in sorted(XCTEST_NAMES)],
                               "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
                               "SWIFT_ACTIVE_COMPILATION_CONDITIONS=", "ENABLE_TESTABILITY=YES",
                               "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "test"]
                    timeout = 900
                elif name == "enforced-sandbox-smoke":
                    command = [sys.executable, NATIVE / "Tests/store_sandbox_smoke.py", "--run",
                               "--module-dir", inputs["modulePath"].parent, "--output", output / "sandbox"]
                    timeout = 600
                else:
                    command = [sys.executable, PRIVACY, "--run", "--native-root", NATIVE,
                               "--module-cache", inputs["modulePath"].parent, "--version", inputs["version"],
                               "--build", inputs["build"], "--output-root", output / "privacy"]
                    timeout = 360
                before = sha(executable) if name == "release-xctest" and executable else None
                phase = run_logged(command, output / (name + ".log"), timeout)
                phase["name"] = name
                report["phases"].append(phase)
                save_report(report_path, report)
                try:
                    if name == "sustained-600s":
                        receipt = record_receipt(phase, output / "sustained/wrapper-report.json")
                        if receipt.get("timedOut") is True:
                            phase["status"] = "timed_out_or_interrupted"
                            phase["innerTimeoutEvidence"] = "Original owned benchmark wrapper timedOut flag"
                        require(receipt.get("mode") == "sustained" and receipt.get("requestedSeconds") == 600
                                and receipt.get("sampling", {}).get("requested") is False
                                and receipt.get("moduleOutputs") == inputs["module"]["outputs"]
                                and receipt.get("sourceChangedDuringRun") is False,
                                "Sustained receipt does not identify the original unsampled frozen workload")
                        require(receipt.get("unsampledBurstAcceptance") is True,
                                "Original strict sustained performance gates failed; failure retained")
                    elif name == "unsigned-store-build":
                        receipt = record_receipt(phase, candidate / "store-candidate-receipt.json")
                        if receipt.get("sourceFingerprint") != FINAL_FINGERPRINT:
                            phase.update({"inputChangeObserved": True, "sourceAndModuleUnchanged": False,
                                          "status": "invalidated_by_input_changes"})
                        possible = candidate / "derived-data/Build/Products/Release/DaBin.app/Contents/MacOS/DaBin"
                        require(possible.is_file() or phase["status"] != "passed",
                                "Successful unsigned build is missing its executable")
                        if possible.is_file():
                            executable = possible
                            require(sha(executable) == receipt.get("executableSHA256"), "Unsigned executable differs from its receipt")
                        require(receipt.get("sourceFingerprint") == FINAL_FINGERPRINT
                                and receipt.get("inputsUnchanged") is True
                                and receipt.get("xcodebuildExitCode") == 0 and receipt.get("packagingPreflightExitCode") == 0
                                and receipt.get("signed") is False and receipt.get("archiveCreated") is False
                                and receipt.get("uploaded") is False,
                                "Unsigned Store compile/preflight receipt failed or differs from the freeze")
                    elif name == "release-xctest":
                        phase["unsignedExecutableBeforeSHA256"] = before
                        try:
                            # Preserve the result bundle before any assertion
                            # about the separate candidate can fail.
                            xctest_evidence(phase, temporary, output)
                        finally:
                            after = sha(executable) if executable is not None and executable.is_file() else None
                            phase["unsignedExecutableAfterSHA256"] = after
                            phase["unsignedExecutablePreserved"] = None if executable is None else after == before
                        if executable:
                            require(phase["unsignedExecutablePreserved"], "XCTest changed the separate unsigned executable")
                    elif name == "enforced-sandbox-smoke":
                        receipt = record_receipt(phase, output / "sandbox/report.json")
                        if receipt.get("testSHA256") != inputs["freeze"]["testSHA256"]["Tests/StoreSandboxSmokeTests.swift"]:
                            phase.update({"inputChangeObserved": True, "sourceAndModuleUnchanged": False,
                                          "status": "invalidated_by_input_changes"})
                        if "timed out after" in receipt.get("error", "").lower():
                            phase["status"] = "timed_out_or_interrupted"
                            phase["innerTimeoutEvidence"] = receipt["error"]
                        phase["signingScope"] = "Ad-hoc '-' signature only on the newly owned synthetic fixture and copied library"
                        require(receipt.get("passed") is True and receipt.get("externalFixturePreserved") is True
                                and receipt.get("externalFixtureRemoved") is True
                                and receipt.get("moduleInputs") == inputs["module"]["inputs"]
                                and receipt.get("testSHA256") == inputs["freeze"]["testSHA256"]["Tests/StoreSandboxSmokeTests.swift"]
                                and receipt.get("moduleSHA256") == inputs["module"]["outputs"]["libDaBinTestCore.dylib"],
                                "Enforced synthetic sandbox runtime receipt failed")
                    else:
                        paths = sorted((output / "privacy").glob("*/report.json"))
                        require(len(paths) == 1, "Privacy render must produce exactly one new receipt")
                        receipt = record_receipt(phase, paths[0])
                        if receipt.get("inputs", {}).get("testSHA256") != inputs["freeze"]["testSHA256"]["Tests/PrivacyRenderTests.swift"]:
                            phase.update({"inputChangeObserved": True, "sourceAndModuleUnchanged": False,
                                          "status": "invalidated_by_input_changes"})
                        if any(receipt.get(step, {}).get("status") == "timeout" for step in ("compile", "execute")):
                            phase["status"] = "timed_out_or_interrupted"
                            phase["innerTimeoutEvidence"] = "Privacy supplement compile/execute timeout receipt"
                        require(receipt.get("status") == "PASS" and receipt.get("sourceAndModuleUnchanged") is True
                                and receipt.get("inputs", {}).get("moduleOutputs") == inputs["module"]["outputs"]
                                and len(receipt.get("renders", [])) == 4, "Privacy render receipt failed or lacks the four current images")
                except (OSError, ValueError, KeyError) as error:
                    phase["status"] = "failed" if phase["status"] == "passed" else phase["status"]
                    phase["verificationError"] = str(error)
                if phase.get("inputChangeObserved"):
                    report["sourceAndModuleUnchanged"] = False
                    abort = "An inner runner observed changed inputs; restored hashes cannot validate that phase"
                    save_report(report_path, report)
                    break
                unchanged(inputs)
                phase["sourceAndModuleUnchanged"] = True
                save_report(report_path, report)
                if phase["status"] == "timed_out_or_interrupted":
                    phase["ownedChildCleanup"] = ("Outer owned group was signalled; independently sessioned nested child cleanup remains unverified"
                        if phase.get("outerTimedOutOrInterrupted") else "Inner runner timeout receipt retained; no subsequent stage will start")
                    abort = "Owned stage timed out or was interrupted; no following stage may compete with an unfinished child"
                    break
        except (OSError, ValueError, KeyError, KeyboardInterrupt) as error:
            abort = str(error) or "Interrupted"
            try:
                unchanged(inputs)
            except (OSError, ValueError, KeyError):
                report["sourceAndModuleUnchanged"] = False
        if abort:
            report["abortReason"] = abort
            attempted = {p["name"] for p in report["phases"]}
            for name in STAGES:
                if name not in attempted:
                    report["phases"].append({"name": name, "status": "not_run", "reason": abort})
        report["status"] = "failed" if (abort or inputs["baselineFailedSuites"]
            or any(p["status"] != "passed" for p in report["phases"])) else "passed"
        report["finishedUTC"] = utc()
        save_report(report_path, report)
    print(report_path)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
