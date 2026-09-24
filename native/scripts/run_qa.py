#!/usr/bin/env python3
"""Run every requested suite and retain machine-readable results, including failures."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time
from project_inventory import ROOT, TARGET, sources, resources, hashes, fingerprint

NONFOCUS = ["ThemeSettingsTests", "PrivacyInformationTests", "DomainTests", "ArchiveLayoutTests",
            "ArchiveStoreTests", "CaptureRemovalTests", "ServiceTests", "QAStorageScopedSaveTests",
            "QALifecycleTests", "ApplicationLifecycleTests", "PreviewLifecycleTests", "TaskStateTests", "CaptureActionTests",
            "CaptureClipboardTests",
            "HourlyGroupingTests", "DayExportTests", "DayExportUITests", "WeeklyStateTests", "InputTests", "AutoCaptureServiceTests", "AutoCaptureRobotPresenterTests", "AutoCaptureRobotCelebrationTests",
            "SoftwareUpdateTests", "UpdateConfigurationTests", "RobotMotionTests"]
WINDOW = ["WindowTests", "WeeklyWindowTests", "FilterResizeTests", "RobotDropTests", "DailyCaptureTests", "HeaderInteractionTests"]
MODULE = "DaBinTestCore"


def capture(arguments):
    try:
        return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        return str(error)


def operation(arguments, log, timeout):
    started = time.monotonic()
    with log.open("w") as stream:
        try:
            process = subprocess.run([str(arg) for arg in arguments], cwd=ROOT,
                                     stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            code, status = process.returncode, "passed" if process.returncode == 0 else "failed"
        except subprocess.TimeoutExpired:
            code, status = None, "timed_out"
        except OSError as error:
            stream.write(str(error) + "\n")
            code, status = None, "launch_failed"
    return {"status": status, "exitCode": code, "seconds": round(time.monotonic() - started, 3),
            "log": str(log.relative_to(ROOT))}


def input_snapshot(selected):
    paths = sources() + resources() + [ROOT / f"Tests/{name}.swift" for name in selected]
    paths += [ROOT / "scripts/run_qa.py", ROOT / "scripts/test.sh", ROOT / "scripts/project_inventory.py",
              ROOT / "Resources/Info.plist", ROOT / "Resources/DaBin.entitlements"]
    if "DomainTests" in selected:
        paths.append(ROOT / "Handoff/implementation/search-cases.json")
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "MISSING"
            for path in sorted(set(paths))}


def cache_valid(stamp, outputs, inputs):
    try:
        saved = json.loads(stamp.read_text())
        return saved["inputs"] == inputs and saved["outputs"] == {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}
    except (OSError, KeyError, ValueError):
        return False


def cache_save(stamp, outputs, inputs):
    stamp.write_text(json.dumps({"inputs": inputs, "outputs": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}}, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storage-only", action="store_true", help="Run all non-focus suites, including isolated lifecycle integration")
    parser.add_argument("--configuration", choices=["Release", "Debug"], default="Release")
    parser.add_argument("--only", action="append", choices=NONFOCUS + WINDOW, help="Run named suite(s); report is explicitly partial")
    parser.add_argument("--timeout", type=int, default=180, help="Seconds allowed per executable")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list:
        print("\n".join(NONFOCUS + WINDOW)); return 0
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.only and args.storage_only:
        parser.error("Choose --only or --storage-only, not both")
    os.chdir(ROOT)
    selected = args.only or (NONFOCUS if args.storage_only else NONFOCUS + WINDOW)
    selected = list(dict.fromkeys(selected))
    started = datetime.datetime.now(datetime.timezone.utc)
    run_dir = ROOT / "build/qa/runs" / started.strftime("%Y%m%dT%H%M%S%fZ")
    run_dir.mkdir(parents=True)
    inputs = input_snapshot(selected)
    initial_fingerprint = fingerprint(inputs)
    compiler = capture(["xcrun", "swiftc", "--version"])
    sdk_version = capture(["xcrun", "--sdk", "macosx", "--show-sdk-version"])
    report = {"schemaVersion": 1, "startedAtUTC": started.isoformat(),
              "configuration": args.configuration, "target": TARGET,
              "coverage": "selected_suites" if args.only else "non_focus_suites" if args.storage_only else "full_registered_suite",
              "sourceFingerprint": initial_fingerprint, "inputs": inputs,
              "swiftVersion": compiler, "sdkVersion": sdk_version,
              "os": capture(["sw_vers"]), "architecture": platform.machine(),
              "guiSessionRequirement": "Window suites require an unlocked, logged-in macOS session; focus failures remain failures.",
              "suites": []}
    module_inputs = {"sources": hashes(sources(False)), "compiler": compiler,
                     "sdk": sdk_version, "target": TARGET, "configuration": args.configuration,
                     "runner": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                     "inventory": hashlib.sha256((ROOT / "scripts/project_inventory.py").read_bytes()).hexdigest()}
    cache = ROOT / "build/qa-cache" / fingerprint(module_inputs)
    cache.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/ModuleCache").mkdir(exist_ok=True)
    library = cache / f"lib{MODULE}.dylib"
    module = cache / f"{MODULE}.swiftmodule"
    cache_stamp = cache / "module-ready.json"
    optimization = ["-O", "-whole-module-optimization"] if args.configuration == "Release" else ["-Onone", "-D", "DEBUG"]
    common = ["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET,
              "-module-cache-path", ROOT / "build/ModuleCache", "-warnings-as-errors",
              "-D", "DABIN_DIRECT_UPDATES", "-parse-as-library", *optimization]
    if cache_valid(cache_stamp, [library, module], module_inputs):
        module_result = {"status": "passed", "cached": True, "seconds": 0}
    else:
        print(f"Compiling {args.configuration} test module ({len(sources(False))} production sources)…", flush=True)
        module_result = operation([*common, "-emit-library", "-emit-module", "-enable-testing",
                                   "-module-name", MODULE, "-emit-module-path", module,
                                   "-Xlinker", "-install_name", "-Xlinker", f"@rpath/lib{MODULE}.dylib",
                                   *sources(False), "-o", library], run_dir / "production-module.log", 300)
        module_result["cached"] = False
        if module_result["status"] == "passed":
            if input_snapshot(selected) == inputs:
                cache_save(cache_stamp, [library, module], module_inputs)
            else:
                module_result["status"] = "invalidated_by_source_changes"
    report["productionModule"] = module_result
    for name in NONFOCUS + WINDOW:
        if name not in selected:
            report["suites"].append({"name": name, "status": "not_requested"})
            continue
        suite = {"name": name, "requiresWindowFocus": name in WINDOW}
        if module_result["status"] != "passed":
            suite["status"] = "blocked_by_compile_failure"
            report["suites"].append(suite)
            print(f"BLOCKED {name}: production module did not compile", flush=True)
            continue
        test = ROOT / f"Tests/{name}.swift"
        if not test.is_file():
            suite["status"] = "missing_test_source"
            report["suites"].append(suite)
            print(f"FAILED {name}: missing test source", flush=True)
            continue
        test_hash = hashlib.sha256(test.read_bytes()).hexdigest()
        test_dir = cache / f"{name}-{test_hash[:16]}"
        test_dir.mkdir(exist_ok=True)
        executable = test_dir / name
        wrapper = test_dir / f"{name}.swift"
        # @testable retains internal access without editing the source tests.
        wrapper.write_text(f"@testable import {MODULE}\n" + test.read_text())
        for resource in resources():
            shutil.copyfile(resource, test_dir / resource.name)
        test_stamp = test_dir / "executable-ready.json"
        test_inputs = {"testSHA256": test_hash, "production": module_inputs}
        if cache_valid(test_stamp, [executable], test_inputs):
            compiled = {"status": "passed", "cached": True, "seconds": 0}
        else:
            compiled = operation([*common, "-I", cache, "-L", cache, f"-l{MODULE}",
                                  "-Xlinker", "-rpath", "-Xlinker", cache,
                                  wrapper, "-o", executable], run_dir / f"{name}-compile.log", 180)
            compiled["cached"] = False
            if compiled["status"] == "passed":
                cache_save(test_stamp, [executable], test_inputs)
            else:
                executable.unlink(missing_ok=True)
                test_stamp.unlink(missing_ok=True)
        suite["compile"] = compiled
        if compiled["status"] != "passed":
            suite["status"] = "compile_failed"
        else:
            arguments = [executable]
            if name == "DomainTests": arguments.append(ROOT / "Handoff/implementation/search-cases.json")
            result = operation(arguments, run_dir / f"{name}.log", args.timeout)
            suite.update(result)
            output = (ROOT / result["log"]).read_text(errors="replace")
            suite["reportedSummary"] = next((line for line in reversed(output.splitlines())
                                             if re.search(r"(?:PASS:|checks? passed|checks?;|failed)", line)), "")
        report["suites"].append(suite)
        print(f"{suite['status'].upper()} {name}" + (": " + suite["reportedSummary"] if suite.get("reportedSummary") else ""), flush=True)
    current = input_snapshot(selected)
    report["sourceChangedDuringRun"] = current != inputs
    requested = [suite for suite in report["suites"] if suite["status"] != "not_requested"]
    report["passedSuites"] = sum(suite["status"] == "passed" for suite in requested)
    report["failedSuites"] = len(requested) - report["passedSuites"]
    report["finishedAtUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    report["status"] = "invalidated_by_source_changes" if current != inputs else "failed" if report["failedSuites"] else "passed"
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    (run_dir / "report.json").write_text(payload)
    (ROOT / "build/qa/latest-run.json").write_text(payload)
    print(f"QA {report['status']}: {report['passedSuites']}/{len(requested)} requested suites passed. Report: {run_dir / 'report.json'}", flush=True)
    return 0 if report["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())
