#!/usr/bin/env python3
"""Collect existing refactor evidence only; never compile, test, launch, or edit sources."""
import argparse
import ast
from collections import Counter
import datetime
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import plistlib
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
NATIVE = ROOT / "working/native"
TEXT_ARTIFACTS = {".json", ".log", ".txt"}


def digest(path):
    if not path.is_file():
        return "MISSING"
    with path.open("rb") as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def fingerprint(values):
    return hashlib.sha256(json.dumps(values, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def safe_join(base, name):
    part = Path(name)
    if part.is_absolute() or ".." in part.parts:
        raise ValueError("Artifact path leaves its declared root: " + str(name))
    path = base / part
    if not path.resolve().is_relative_to(base.resolve()):
        raise ValueError("Artifact symlink leaves its declared root: " + str(name))
    return path


def read_json(path):
    if not path.is_file():
        return {"state": "pending", "path": relative(path)}
    try:
        return {"state": "available", "path": relative(path), "sha256": digest(path),
                "data": json.loads(path.read_text())}
    except (OSError, ValueError) as error:
        return {"state": "invalid_or_incomplete", "path": relative(path), "error": str(error)}


def compare_inputs(base, expected):
    observed = {}
    differences = []
    for name, wanted in sorted(expected.items()):
        try:
            actual = digest(safe_join(base, name))
        except (OSError, ValueError) as error:
            actual = "ERROR: " + str(error)
        observed[name] = actual
        if actual != wanted:
            differences.append({"path": name, "expected": wanted, "actual": actual})
    return {"inputCount": len(expected), "matched": not differences, "differences": differences,
            "observedFingerprint": fingerprint(observed), "expectedFingerprint": fingerprint(expected)}


def registry(path):
    """Read literal registry declarations without executing the QA runner."""
    values = {"NONFOCUS": [], "WINDOW": []}
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in values:
                    values[target.id] = ast.literal_eval(node.value)
        elif isinstance(node, ast.AugAssign) and isinstance(node.target, ast.Name) and node.target.id in values:
            if not isinstance(node.op, ast.Add):
                raise ValueError("Unsupported registry mutation")
            values[node.target.id] += ast.literal_eval(node.value)
        elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            call = node.value
            if isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name) and call.func.value.id in values:
                if call.func.attr != "append" or len(call.args) != 1:
                    raise ValueError("Unsupported registry mutation")
                values[call.func.value.id].append(ast.literal_eval(call.args[0]))
    return values


def load_inventory(native, label):
    spec = importlib.util.spec_from_file_location("verification_inventory_" + label,
                                                native / "scripts/project_inventory.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def log_findings(paths):
    warnings, limitations, failures, measurements = [], [], [], []
    for path in sorted(set(paths)):
        if not path.is_file():
            continue
        compile_log = path.name.endswith("-compile.log") or path.name == "production-module.log" or path.name.startswith("xcodebuild")
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            item = {"path": relative(path), "line": number, "text": line}
            if re.search(r'\bwarning(?:s)?"?\s*:', line, re.IGNORECASE):
                if re.search(r'warnings"?\s*:\s*\[\s*\]', line, re.IGNORECASE):
                    continue
                category = ("table_reentrancy" if "NSTableView" in line and re.search(r"re.?entran|layout|delegate", line, re.IGNORECASE)
                            else "actor_compile" if compile_log and re.search(r"actor.?isolated|main actor|nonisolated", line, re.IGNORECASE)
                            else "compile" if compile_log else "runtime_or_metric_summary")
                location = re.search(r"(.+\.swift):(\d+):(\d+):\s*warning:", line)
                if location:
                    item["sourceLocation"] = {"path": location.group(1).strip(), "line": int(location.group(2)),
                                              "column": int(location.group(3))}
                warnings.append(dict(item, category=category))
            if re.search(r"\bSKIP(?:PED)?\b|fallback|not physical|no timing threshold|not a heap.leak", line, re.IGNORECASE):
                limitations.append(item)
            if re.search(r"^FAIL(?:ED|URE)?(?:\b|:)|fatal error:|Assertion failed|assertion failure|\berror:", line, re.IGNORECASE):
                failures.append(item)
            if re.search(r"^(?:SEED|ACTION_COUNTS|ROUTE_COUNTS|DURABILITY|NATIVE_CONTROL_COUNTS|CONTROL_BOUNDARY|BOUNDARIES|CHECKPOINT):?\s", line):
                measurements.append(item)
    return {"warnings": warnings, "warningCounts": dict(Counter(item["category"] for item in warnings)),
            "limitations": limitations, "failureLines": failures, "runtimeMetricAndBoundaryLines": measurements}


def unittest_result(log, result_path):
    record = read_json(result_path)
    if not log.is_file():
        return {"state": "pending", "result": record}
    text = log.read_text(errors="replace")
    ran = re.search(r"^Ran (\d+) tests? in ([\d.]+)s", text, re.MULTILINE)
    cases = [{"name": match.group(1), "identity": match.group(2), "status": match.group(3)}
             for match in re.finditer(r"^(\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$", text, re.MULTILINE)]
    return {"state": "available" if ran else "incomplete", "log": relative(log), "result": record,
            "tests": int(ran.group(1)) if ran else None, "seconds": float(ran.group(2)) if ran else None,
            "caseStatusCounts": dict(Counter(case["status"] for case in cases)), "cases": cases,
            "failures": [case for case in cases if case["status"] in {"FAIL", "ERROR"}],
            "passed": bool(re.search(r"^OK(?:\s|$)", text, re.MULTILINE))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-complete", action="store_true", help="Exit 2 if final artifacts are still pending; 1 for integrity mismatches")
    parser.add_argument("--output", type=Path, default=ROOT / "verification-collected.json")
    args = parser.parse_args()
    baseline = read_json(ROOT / "baseline.json")
    live = Path(baseline.get("data", {}).get("repository", "/Users/roeylibfeld/Documents/KARI Creatives/DaBin"))
    output = args.output.resolve()
    if output.is_relative_to((ROOT / "working").resolve()) or output.is_relative_to(live.resolve()):
        parser.error("Collector output must stay outside frozen and live sources")
    problems, pending = [], []
    freeze = read_json(ROOT / "source-freeze.json")
    frozen = freeze.get("data", {})
    frozen_registry = frozen.get("registry", [])
    result = {"schemaVersion": 1, "collectedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "Existing refactor verification evidence only; no workload execution or source writes. Native timing is synthetic input/layout and runloop intervals. No performance-cause, leak, physical-latency, signed-readiness or delivery inference.",
              "freeze": freeze, "liveRepository": str(live), "expectedRegisteredSuites": 132}
    if freeze["state"] != "available":
        pending.append("source-freeze.json")
    else:
        snapshot = compare_inputs(ROOT / "working", frozen["fullSnapshotInputs"])
        live_match = compare_inputs(live, frozen["fullSnapshotInputs"])
        result["frozenInputs"] = {"snapshot": snapshot, "live": live_match}
        for label, check in (("snapshot", snapshot), ("live", live_match)):
            if not check["matched"]:
                problems.append(label + " no longer matches full frozen input map")

    inventories = {}
    for label, native in (("snapshot", NATIVE), ("live", live / "native")):
        try:
            inventory = load_inventory(native, label)
            build_inputs = inventory.build_inventory()
            groups = registry(native / "scripts/run_qa.py")
            names = groups["NONFOCUS"] + groups["WINDOW"]
            inventories[label] = inventory
            check = {"fingerprint": fingerprint(build_inputs), "matchesFrozenProductionInputs": build_inputs == frozen.get("productionInputs"),
                     "matchesFrozenProductionFingerprint": fingerprint(build_inputs) == frozen.get("productionFingerprint"),
                     "productionInputCount": len(build_inputs), "sourceCount": len(inventory.sources()),
                     "sourcePaths": [str(path.relative_to(native)) for path in inventory.sources()],
                     "registry": names, "nonFocusCount": len(groups["NONFOCUS"]), "windowCount": len(groups["WINDOW"]),
                     "registryMatchesFrozen": names == frozen_registry, "uniqueRegistry": len(names) == len(set(names))}
            expected_tests = {name for name in frozen.get("fullSnapshotInputs", {}) if name.startswith("native/Tests/") and name.endswith(".swift")}
            actual_tests = {"native/" + str(path.relative_to(native)) for path in (native / "Tests").glob("*.swift")}
            check["flatTestInventoryDifferences"] = {"added": sorted(actual_tests - expected_tests), "missing": sorted(expected_tests - actual_tests)}
            result.setdefault("currentInventories", {})[label] = check
            if not all((check["matchesFrozenProductionInputs"], check["matchesFrozenProductionFingerprint"],
                        check["registryMatchesFrozen"], check["uniqueRegistry"], len(names) == 132, actual_tests == expected_tests)):
                problems.append(label + " production inventory or registry mismatch")
        except (OSError, ValueError, KeyError) as error:
            problems.append(label + " inventory unavailable: " + str(error))

    native_reports, native_logs, expected_receipts = {}, set(), {}
    for label in ("focused-regression", "full-native", "sustained-speed"):
        artifact = read_json(ROOT / (label + "-native-report.json"))
        launch = read_json(ROOT / (label + "-launch.json"))
        stage = {"report": artifact, "launch": launch, "cacheVerification": read_json(ROOT / (label + "-compiled-output-verification.json"))}
        result.setdefault("nativeStages", {})[label] = stage
        if artifact["state"] != "available":
            pending.append(label + " native report")
            continue
        for key in ("launch", "cacheVerification"):
            if stage[key]["state"] != "available":
                pending.append(label + " " + key)
        if stage["cacheVerification"]["state"] == "available":
            archive_checks = []
            for name, saved in stage["cacheVerification"]["data"].items():
                current_receipt = safe_join(NATIVE, name)
                matched = saved.get("outputHashesVerified") is True and saved.get("receiptSHA256") == digest(current_receipt)
                archive_checks.append({"receipt": name, "archivedReceiptStillMatches": matched})
                if not matched:
                    problems.append(label + " archived cache verification mismatch: " + name)
            stage["archivedCacheVerificationChecks"] = archive_checks
        report = artifact["data"]
        native_reports[label] = report
        requested = [suite for suite in report.get("suites", []) if suite.get("status") != "not_requested"]
        statuses = Counter(suite.get("status", "MISSING") for suite in requested)
        names = [suite["name"] for suite in requested]
        report_names = [suite["name"] for suite in report.get("suites", [])]
        stage.update(requestedCount=len(requested), requestedSuites=names, statusCounts=dict(statuses),
                     failedSuites=[suite for suite in requested if suite.get("status") != "passed"],
                     reportRegistryMatchesFrozen=report_names == frozen_registry,
                     reportedFingerprintRecomputed=fingerprint(report.get("inputs", {})),
                     snapshotInputComparison=compare_inputs(NATIVE, report.get("inputs", {})),
                     liveInputComparison=compare_inputs(live / "native", report.get("inputs", {})))
        desired = frozen_registry if label == "full-native" else ["WorkspaceZoomPerformanceTests"] if label == "sustained-speed" else None
        if desired is not None:
            stage["requestedMatchesExpected"] = names == desired
        if (report_names != frozen_registry or len(report_names) != len(set(report_names))
                or report.get("sourceChangedDuringRun") is not False
                or report.get("passedSuites") != statuses["passed"]
                or report.get("failedSuites") != len(requested) - statuses["passed"]
                or report.get("sourceFingerprint") != stage["reportedFingerprintRecomputed"]
                or not stage["snapshotInputComparison"]["matched"] or not stage["liveInputComparison"]["matched"]
                or (desired is not None and names != desired)
                or report.get("configuration") != "Release" or report.get("distribution") != "app-store"
                or report.get("compileDefinitions") != []
                or (label == "full-native" and report.get("coverage") != "full_registered_suite")):
            problems.append(label + " report count, scope, registry or fingerprint mismatch")
        if launch["state"] == "available":
            stage["reportBelongsToLaunch"] = report.get("startedAtUTC", "") >= launch["data"].get("startedAtUTC", "")
            if not stage["reportBelongsToLaunch"]:
                problems.append(label + " report predates launch")
        paths = [report.get("productionModule", {}).get("log")]
        for suite in requested:
            paths.extend((suite.get("log"), suite.get("compile", {}).get("log")))
        run_dirs = {safe_join(NATIVE, path).parent for path in paths if path}
        logs = {path for directory in run_dirs for path in directory.glob("*.log")}
        native_logs.update(logs)
        stage["runDirectories"] = [relative(path) for path in sorted(run_dirs)]
        stage["logFindings"] = log_findings(logs)
        if "snapshot" in inventories:
            inventory = inventories["snapshot"]
            module_inputs = {"sources": inventory.hashes(inventory.sources(False)), "compiler": report["swiftVersion"],
                             "sdk": report["sdkVersion"], "target": report["target"], "configuration": report["configuration"],
                             "distribution": report["distribution"], "compileDefinitions": report["compileDefinitions"],
                             "runner": digest(NATIVE / "scripts/run_qa.py"), "inventory": digest(NATIVE / "scripts/project_inventory.py")}
            cache = NATIVE / "build/qa-cache" / (report["distribution"] + "-" + fingerprint(module_inputs))
            if report.get("productionModule", {}).get("status") == "passed":
                expected_receipts[cache / "module-ready.json"] = module_inputs
                for suite in requested:
                    if suite.get("compile", {}).get("status") == "passed":
                        test_hash = report["inputs"].get("Tests/" + suite["name"] + ".swift")
                        if test_hash:
                            expected_receipts[cache / (suite["name"] + "-" + test_hash[:16]) / "executable-ready.json"] = {
                                "testSHA256": test_hash, "production": module_inputs}

    cache_results = []
    receipts = set((NATIVE / "build/qa-cache").rglob("module-ready.json")) | set((NATIVE / "build/qa-cache").rglob("executable-ready.json")) | set(expected_receipts)
    for path in sorted(receipts):
        receipt = read_json(path)
        item = {"receipt": receipt, "requiredByCompletedReport": path in expected_receipts}
        if receipt["state"] == "available":
            saved = receipt["data"]
            item["outputComparison"] = compare_inputs(path.parent, saved.get("outputs", {}))
            item["hasOutputHashes"] = bool(saved.get("outputs"))
            if path in expected_receipts:
                item["inputsMatchReport"] = saved.get("inputs") == expected_receipts[path]
            if not item["hasOutputHashes"] or not item["outputComparison"]["matched"] or item.get("inputsMatchReport") is False:
                problems.append("Cache receipt mismatch: " + relative(path))
        elif path in expected_receipts:
            problems.append("Completed report has no valid cache receipt: " + relative(path))
        cache_results.append(item)
    result["compiledReceipts"] = {"count": len(cache_results), "requiredCount": len(expected_receipts), "receipts": cache_results}

    metrics = []
    metric_paths = {path for path in (ROOT / "outputs").rglob("*.json") if "stress" in path.name or "performance" in path.name}
    metric_paths.update(path for path in (ROOT / "working/docs/qa").rglob("*.json") if "stress" in path.name)
    metric_paths.update(path for path in (NATIVE / "build/qa").rglob("*.json") if "stress" in path.name or "performance" in path.name)
    for path in sorted(metric_paths):
        item = read_json(path)
        if item["state"] == "available" and path.name == "performance.json":
            data = item["data"]
            gates = data.get("performanceGates", {})
            values = [data.get("inputToLayoutP95Milliseconds"), data.get("steadyZoomTimerP95Milliseconds")]
            finite_values = all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) for value in values)
            item["strictGateObservation"] = {"inputToLayoutP95Milliseconds": data.get("inputToLayoutP95Milliseconds"),
                "steadyZoomTimerP95Milliseconds": data.get("steadyZoomTimerP95Milliseconds"), "recordedGates": gates,
                "inputWithin50ms": finite_values and values[0] <= 50,
                "timerWithin33ms": finite_values and values[1] <= 33}
            recorded_pass_matches = gates.get("passed") == (finite_values and values[0] <= 50 and values[1] <= 33)
            if (not finite_values or gates.get("inputToLayoutP95MaximumMilliseconds") != 50
                    or gates.get("steadyZoomTimerP95MaximumMilliseconds") != 33 or not recorded_pass_matches):
                problems.append("Recorded strict timing gates or observations are inconsistent: " + relative(path))
            stage_name = path.relative_to(ROOT / "outputs").parts[0] if path.is_relative_to(ROOT / "outputs") else None
            if stage_name == "sustained-speed" and (data.get("requestedDurationSeconds") != 600 or data.get("fullTenMinuteRun") is not True):
                problems.append("Sustained metric does not record the requested 600 second workload")
        metrics.append(item)
    result["metrics"] = metrics
    for label in ("full-native", "sustained-speed"):
        performance_path = ROOT / "outputs" / label / "zoom_performance_qa_output/performance.json"
        if label in native_reports and native_reports[label].get("productionModule", {}).get("status") == "passed" and not performance_path.is_file():
            pending.append(label + " performance.json")

    tools = unittest_result(ROOT / "python-tool-tests.log", ROOT / "python-tool-tests-result.json")
    offline = unittest_result(ROOT / "offline-packaging.log", ROOT / "offline-packaging-result.json")
    inventory_cases = [case for case in tools.get("cases", []) if case["identity"].startswith("test_project_inventory.")]
    expected_metadata_failures = (tools.get("tests") == 69 and len(tools.get("failures", [])) == 3
                                  and all(case["status"] == "FAIL" and case["identity"].startswith("test_app_store_metadata.") for case in tools.get("failures", [])))
    result["tooling"] = {"python": tools, "offlinePreflight": offline, "inventoryCases": inventory_cases,
                         "expectedThreeMetadataFailuresObserved": expected_metadata_failures,
                         "sixInventoryTestsPassed": len(inventory_cases) == 6 and all(case["status"] == "ok" for case in inventory_cases),
                         "offline33Passed": offline.get("tests") == 33 and offline.get("passed") is True}
    if tools["state"] != "available" or offline["state"] != "available":
        pending.append("tooling results")
    elif not all((expected_metadata_failures, result["tooling"]["sixInventoryTestsPassed"], result["tooling"]["offline33Passed"])):
        problems.append("Tooling results differ from expected metadata3/offline33/inventory6")
    try:
        metadata = json.loads((live / "docs/app-store/metadata-en-US.json").read_text())["candidate"]
        info = plistlib.loads((live / "native/Resources/Info.plist").read_bytes())
        result["metadataMismatch"] = {"candidateVersion": metadata["version"], "candidateBuild": metadata["build"],
            "sourceVersion": info["CFBundleShortVersionString"], "sourceBuild": info["CFBundleVersion"],
            "versionMatches": metadata["version"] == info["CFBundleShortVersionString"], "buildMatches": str(metadata["build"]) == str(info["CFBundleVersion"])}
    except (OSError, ValueError, KeyError) as error:
        problems.append("Metadata observation unavailable: " + str(error))

    campaign = read_json(ROOT / "full-campaign-result.json")
    result["campaign"] = campaign
    if campaign["state"] != "available":
        pending.append("full-campaign-result.json")
    else:
        stages = {stage["stage"]: stage for stage in campaign["data"].get("stages", [])}
        result["finalStageResults"] = stages
        for label in ("full-native", "sustained-speed", "unsigned-store-build", "deterministic-project"):
            if label not in stages:
                pending.append(label + " final stage result")
        if campaign["data"].get("snapshotUnchanged") is not True:
            problems.append("Campaign reports changed frozen sources")

    unsigned = [read_json(path) for path in sorted((NATIVE / "build").glob("store-unsigned-*/store-candidate-receipt.json"))]
    result["unsignedStoreCandidates"] = unsigned
    if not unsigned:
        pending.append("unsigned Store candidate receipt")
    for item in unsigned:
        if item["state"] != "available":
            problems.append("Invalid unsigned Store receipt")
            continue
        data = item["data"]
        item["snapshotInputComparison"] = compare_inputs(NATIVE, data.get("inputs", {}))
        item["liveInputComparison"] = compare_inputs(live / "native", data.get("inputs", {}))
        executable = Path(data.get("app", "")) / "Contents/MacOS/DaBin"
        item["executableHashObserved"] = digest(executable) if executable.resolve().is_relative_to(NATIVE.resolve()) else "UNSAFE_PATH"
        item["executableHashMatches"] = item["executableHashObserved"] == data.get("executableSHA256")
        if (not item["snapshotInputComparison"]["matched"] or not item["liveInputComparison"]["matched"]
                or data.get("sourceFingerprint") != frozen.get("productionFingerprint")
                or (data.get("xcodebuildExitCode") == 0 and not item["executableHashMatches"])):
            problems.append("Unsigned Store receipt input or executable mismatch")
        for name in ("buildLog", "preflightLog"):
            path = Path(data.get(name, ""))
            if path.is_file() and path.resolve().is_relative_to(NATIVE.resolve()):
                native_logs.add(path)
    result["allNativeAndBuildLogFindings"] = log_findings(native_logs)

    artifact_paths = {path for path in ROOT.iterdir() if path.is_file() and path.suffix in TEXT_ARTIFACTS}
    for directory in (ROOT / "outputs", NATIVE / "build/qa", ROOT / "working/docs/qa"):
        artifact_paths.update(path for path in directory.rglob("*") if path.is_file() and path.suffix in TEXT_ARTIFACTS)
    artifact_paths.update(receipts)
    for item in unsigned:
        receipt_path = ROOT / item["path"]
        artifact_paths.add(receipt_path)
        artifact_paths.update(path for path in receipt_path.parent.glob("*") if path.is_file() and path.suffix in TEXT_ARTIFACTS)
    index_path = ROOT / "verification-artifact-hashes.json"
    artifact_paths.difference_update({output, index_path})
    index = {relative(path): {"sha256": digest(path), "bytes": path.stat().st_size}
             for path in sorted(artifact_paths) if path.is_file()}
    index_path.write_text(json.dumps({"scope": "Existing JSON reports/metrics/receipts and text logs only; binary/image outputs excluded from this index. Compiled binaries are verified separately through receipts.",
                                     "artifacts": index}, indent=2, sort_keys=True) + "\n")
    result["rawArtifactIndex"] = {"path": relative(index_path), "sha256": digest(index_path), "count": len(index)}
    result["integrityProblems"] = problems
    result["pendingArtifacts"] = list(dict.fromkeys(pending))
    workload_failures = {label: report.get("failedSuites") for label, report in native_reports.items() if report.get("status") != "passed"}
    result["nativeWorkloadFailures"] = workload_failures
    result["collectionStatus"] = "pending" if pending else "integrity_mismatch" if problems else "complete_with_native_failures" if workload_failures else "complete"
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"collectionStatus": result["collectionStatus"], "output": str(output),
                      "artifactHashIndex": str(index_path), "pendingArtifacts": result["pendingArtifacts"],
                      "integrityProblems": problems, "nativeWorkloadFailures": workload_failures}, indent=2))
    return 2 if args.require_complete and pending else 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
