#!/usr/bin/env python3
"""Run one verified, owned native zoom fixture and preserve bounded evidence.

This script never builds, changes native inputs, activates applications, reads
personal data, or signals another process. Profile mode samples only its own
benchmark PID after the first completed cycle proves the workload has started.
Sampled timing is diagnostic and is never relabeled as unsampled acceptance.

Examples (run only after the parent freezes native inputs and authorizes it):
  python3 profile_workspace_zoom.py --run-report /absolute/path/report.json
  python3 profile_workspace_zoom.py --module-receipt /absolute/path/module-ready.json
  python3 profile_workspace_zoom.py --run-report /absolute/path/report.json --mode sustained
  python3 profile_workspace_zoom.py --run-report /absolute/path/report.json --mode retention

Sustained mode runs the original burst workload for 600 seconds without a
profiler. Retention mode uses the existing fixed-data option, is explicitly
diagnostic, and cannot certify the original burst workload. Both retain the
same native gates. Exact wait4 resource usage belongs to the benchmark PID;
there is no periodic ps/footprint subprocess that competes with the workload.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import time
import uuid

SUITE = "WorkspaceZoomPerformanceTests"
HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]
NATIVE = REPOSITORY / "native"
CACHE = NATIVE / "build/qa-cache"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object in {path}")
    return value


def under(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def current_sources() -> dict[str, str]:
    return {str(p.relative_to(NATIVE)): sha(p)
            for p in sorted((NATIVE / "Sources/DaBin").glob("*.swift"))
            if p.name != "DaBinMain.swift"}


def verify_module(receipt_path: Path, campaign: dict | None = None) -> tuple[Path, dict]:
    receipt_path = receipt_path.resolve()
    if not under(receipt_path, CACHE.resolve()) or receipt_path.name != "module-ready.json":
        raise ValueError("Refusing a module receipt outside the native QA cache")
    receipt = read_json(receipt_path)
    inputs = receipt["inputs"]
    if inputs.get("configuration") != "Release" or inputs.get("distribution") not in ("direct", "app-store"):
        raise ValueError("A verified direct or App Store Release module is required")
    definitions = ["DABIN_DIRECT_UPDATES"] if inputs["distribution"] == "direct" else []
    if inputs.get("compileDefinitions") != definitions:
        raise ValueError("Release compilation definitions do not match the declared channel")
    if receipt_path.parent.name != inputs["distribution"] + "-" + fingerprint(inputs):
        raise ValueError("The module-cache directory does not match its full input fingerprint")
    if inputs.get("sources") != current_sources():
        raise ValueError("The cached module does not match the exact current production source inventory")
    for field, relative in [("runner", "scripts/run_qa.py"), ("inventory", "scripts/project_inventory.py")]:
        if inputs.get(field) != sha(NATIVE / relative):
            raise ValueError(f"The cached module does not match the current {field}")
    for name in ["libDaBinTestCore.dylib", "DaBinTestCore.swiftmodule"]:
        if receipt.get("outputs", {}).get(name) != sha(receipt_path.parent / name):
            raise ValueError(f"The module output does not match its receipt: {name}")
    if campaign is not None:
        if campaign.get("configuration") != "Release" or campaign.get("sourceChangedDuringRun") is not False:
            raise ValueError("The campaign must identify frozen Release inputs")
        for field, report_field in [("distribution", "distribution"), ("compiler", "swiftVersion"),
                                    ("sdk", "sdkVersion"), ("target", "target"),
                                    ("compileDefinitions", "compileDefinitions")]:
            if inputs.get(field) != campaign.get(report_field):
                raise ValueError(f"The module differs from the selected campaign's {report_field}")
        for relative, expected in campaign["inputs"].items():
            path = NATIVE / relative
            if not path.is_file() or sha(path) != expected:
                raise ValueError(f"The campaign's frozen input no longer matches: {relative}")
    return receipt_path, receipt


def select_module(args: argparse.Namespace) -> tuple[Path, dict]:
    if args.module_receipt:
        return verify_module(args.module_receipt)
    campaign = read_json(args.run_report.resolve())
    matches: list[tuple[Path, dict]] = []
    for path in sorted(CACHE.glob("*/module-ready.json")):
        try:
            matches.append(verify_module(path, campaign))
        except (OSError, KeyError, ValueError):
            continue
    if len(matches) != 1:
        raise ValueError(f"The campaign must resolve exactly one current Release cache; found {len(matches)}")
    return matches[0]


def verify_test(module_path: Path, module: dict) -> tuple[Path, dict, dict[str, str]]:
    test_hash = sha(NATIVE / f"Tests/{SUITE}.swift")
    test_directory = module_path.parent / f"{SUITE}-{test_hash[:16]}"
    stamp = read_json(test_directory / "executable-ready.json")
    if stamp.get("inputs") != {"testSHA256": test_hash, "production": module["inputs"]}:
        raise ValueError("The benchmark executable was not compiled from the exact module and current test")
    executable = test_directory / SUITE
    if stamp.get("outputs", {}).get(SUITE) != sha(executable) or not os.access(executable, os.X_OK):
        raise ValueError("The benchmark executable does not match its compile receipt")
    resources = {}
    for resource in ["AppIcon.icns", "PrivacyInfo.xcprivacy", "PrivacyPolicy.md", "robot.svg"]:
        resources["Resources/" + resource] = sha(NATIVE / "Resources" / resource)
        if sha(test_directory / resource) != resources["Resources/" + resource]:
            raise ValueError(f"The copied benchmark resource is stale: {resource}")
    return executable, stamp, resources


def poll_owned(process: subprocess.Popen) -> tuple[int, object] | None:
    """Reap only this still-owned child and retain its exact resource accounting."""
    if process.returncode is not None:
        return None
    waited, status, usage = os.wait4(process.pid, os.WNOHANG)
    if waited == 0:
        return None
    process.returncode = os.waitstatus_to_exitcode(status)
    return process.returncode, usage


def stop_owned(process: subprocess.Popen) -> tuple[int, object] | None:
    result = poll_owned(process)
    if result is not None or process.returncode is not None:
        return result
    # An unreaped child PID cannot be recycled. No external PID is accepted.
    try:
        os.kill(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        # The owned child may have exited between wait4 and kill. It remains
        # unreaped, so the PID cannot have been reused by another process.
        return poll_owned(process)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        result = poll_owned(process)
        if result is not None:
            return result
        time.sleep(0.05)
    try:
        os.kill(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    waited, status, usage = os.wait4(process.pid, 0)
    assert waited == process.pid
    process.returncode = os.waitstatus_to_exitcode(status)
    return process.returncode, usage


def record_resources(report: dict, result: tuple[int, object] | None) -> None:
    if result is None:
        return
    code, usage = result
    report["exitCode"] = code
    report["benchmarkResources"] = {"userCPUSeconds": usage.ru_utime,
        "systemCPUSeconds": usage.ru_stime, "maximumRSSBytes": usage.ru_maxrss,
        "cpuPercentOverWholeProcessLifetime": (usage.ru_utime + usage.ru_stime)
            / max(report["wallSeconds"], 0.001) * 100,
        "scope": "Exact wait4 accounting for owned benchmark PID only; maximum RSS units are bytes on macOS; lifetime includes seed, rendering, and cleanup"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--run-report", type=Path)
    source.add_argument("--module-receipt", type=Path)
    parser.add_argument("--mode", choices=["profile", "sustained", "retention"], default="profile")
    parser.add_argument("--output", type=Path, help="New directory beneath this script's QA evidence directory")
    parser.add_argument("--timeout", type=int, help="Bounded wall seconds; default 180 profile / 900 sustained")
    args = parser.parse_args()
    seconds = 30 if args.mode == "profile" else 600
    timeout = args.timeout if args.timeout is not None else (180 if args.mode == "profile" else 900)
    if timeout < seconds + 30 or timeout > 1_200:
        parser.error("Timeout must allow the workload plus 30 seconds and must not exceed 1200 seconds")
    if platform.system() != "Darwin":
        parser.error("Exact owned-child resource accounting and native QA require macOS")

    module_path, module = select_module(args)
    executable, test, resources = verify_test(module_path, module)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or HERE / f"zoom-{args.mode}-{stamp}-{uuid.uuid4().hex[:8]}").resolve()
    if output == HERE or not under(output, HERE):
        parser.error("Output must be a new child directory of docs/qa/full-review-2026-10-05")
    output.mkdir(parents=True, exist_ok=False)
    native_output = output / "native-performance"
    native_output.mkdir()
    report = {
        "schemaVersion": 1, "mode": args.mode, "completed": False,
        "measurementScope": "Owned synthetic native fixture; not physical input/display latency, GPU frame pacing, exhaustive leak detection or distribution sandbox validation",
        "timingInterpretation": "Sampled diagnostic; not unsampled acceptance" if args.mode == "profile"
            else "Unsampled original burst workload" if args.mode == "sustained"
            else "Fixed-data retention diagnostic; not burst acceptance",
        "moduleReceipt": str(module_path), "moduleReceiptSHA256": sha(module_path),
        "moduleInputs": module["inputs"], "moduleOutputs": module["outputs"],
        "testInputs": test["inputs"], "testOutputs": test["outputs"], "resourceSHA256": resources,
        "wrapperSHA256": sha(Path(__file__)), "requestedSeconds": seconds, "timeoutSeconds": timeout,
        "launchCommand": [str(executable)], "workingDirectory": str(NATIVE),
        "stdout": "stdout.log", "stderr": "stderr.log", "nativeReport": "native-performance/performance.json",
        "sampling": {"requested": args.mode == "profile", "completed": False},
    }
    (output / "module-receipt.json").write_text(json.dumps(module, indent=2, sort_keys=True) + "\n")
    (output / "test-receipt.json").write_text(json.dumps(test, indent=2, sort_keys=True) + "\n")
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("DABIN_", "DYLD_"))}
    environment.update({"DABIN_ZOOM_PERFORMANCE_SECONDS": str(seconds),
                        "DABIN_ZOOM_PERFORMANCE_QA_OUTPUT": str(native_output),
                        "DABIN_ZOOM_PERFORMANCE_FIXED_DATA": "1" if args.mode == "retention" else "0"})
    report["fixtureEnvironment"] = {key: value for key, value in environment.items() if key.startswith("DABIN_")}
    process = None
    sample_process = None
    sample_stream = None
    result = None
    started = time.monotonic()
    try:
        with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
            process = subprocess.Popen([str(executable)], cwd=NATIVE, env=environment,
                                       stdout=stdout, stderr=stderr, start_new_session=True)
            report["ownedPID"] = process.pid
            while time.monotonic() - started < timeout:
                result = poll_owned(process)
                if result is not None:
                    break
                if args.mode == "profile" and sample_process is None:
                    # The fixture explicitly fflushes each completed cycle.
                    if "CYCLE:" in (output / "stdout.log").read_text(errors="replace"):
                        sample_stream = (output / "sample-tool.log").open("w")
                        command = ["/usr/bin/sample", str(process.pid), "5", "1", "-file",
                                   str(output / "owned-process-sample.txt")]
                        sample_process = subprocess.Popen(command, stdout=sample_stream, stderr=subprocess.STDOUT)
                        report["sampling"].update({"targetPID": process.pid, "command": command,
                            "trigger": "First completed production-fixture cycle; mixed steady zoom/arrival/idle sample",
                            "secondsAfterLaunch": round(time.monotonic() - started, 3)})
                time.sleep(0.05)
            if result is None:
                report["timedOut"] = True
                result = stop_owned(process)
            report["wallSeconds"] = round(time.monotonic() - started, 3)
            record_resources(report, result)
            if sample_process is not None:
                try:
                    sample_code = sample_process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    sample_process.kill()
                    sample_code = sample_process.wait(timeout=5)
                    report["sampling"]["timedOut"] = True
                report["sampling"].update({"exitCode": sample_code,
                    "completed": sample_code == 0 and (output / "owned-process-sample.txt").is_file()})
            report["completed"] = result is not None and not report.get("timedOut", False)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        if process is not None and process.returncode is None:
            result = stop_owned(process)
            report["wallSeconds"] = round(time.monotonic() - started, 3)
            record_resources(report, result)
        if sample_process is not None and sample_process.poll() is None:
            sample_process.kill()
            sample_process.wait(timeout=5)
        if sample_stream is not None:
            sample_stream.close()
        try:
            verify_module(module_path)
            verify_test(module_path, module)
            report["sourceChangedDuringRun"] = False
        except (OSError, KeyError, ValueError) as error:
            report["sourceChangedDuringRun"] = True
            report["sourceVerificationError"] = str(error)
        performance_path = native_output / "performance.json"
        if performance_path.is_file():
            try:
                report["nativePerformance"] = read_json(performance_path)
            except (OSError, ValueError) as error:
                report["nativeReportError"] = str(error)
        (output / "sample-metadata.json").write_text(json.dumps(report["sampling"], indent=2, sort_keys=True) + "\n")
        report["evidenceSHA256"] = {str(path.relative_to(output)): sha(path)
                                   for path in sorted(output.rglob("*")) if path.is_file()}
        report["strictWorkloadPassed"] = (report.get("exitCode") == 0
            and report.get("nativePerformance", {}).get("performanceGates", {}).get("passed") is True
            and report.get("sourceChangedDuringRun") is False and report["completed"])
        report["unsampledBurstAcceptance"] = args.mode == "sustained" and report["strictWorkloadPassed"]
        (output / "wrapper-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(output / "wrapper-report.json")
    # A measured native gate failure stays a failure even when profiling succeeded.
    return 0 if report["strictWorkloadPassed"] and (args.mode != "profile" or report["sampling"]["completed"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
