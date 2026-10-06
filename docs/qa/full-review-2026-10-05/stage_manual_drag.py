#!/usr/bin/env python3
"""Verify current QA receipts; optionally stage an isolated manual drag app.

Default is read-only. --prepare copies verified outputs to a fresh /private/tmp
bundle and ad-hoc signs those copies. It never compiles, launches, installs,
modifies native inputs, reads the general clipboard, or contacts a network.
The default scope requires a full PASS. Explicit manual-fixture-only scope
retains overall QA failure while requiring current requested functional PASSes.
Run --prepare only after the coordinator finishes native GUI QA.
"""
import argparse
import datetime
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

REPO = Path(__file__).resolve().parents[3]
NATIVE = REPO / "native"
sys.path.insert(0, str(NATIVE / "scripts"))
from project_inventory import build_inventory, fingerprint, hashes, resources, sources
import run_qa as qa


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


PERFORMANCE_SUITE = "WorkspaceZoomPerformanceTests"
PERFORMANCE_BUDGET_MESSAGES = (
    "Synthetic input-to-layout p95 must stay within the existing 50 ms budget; report:",
    "Steady zoom main-runloop p95 must stay within the existing 33 ms budget; report:",
)


def review_reports(paths, scope):
    """Validate evidence only; never compile, stage, sign or run a fixture."""
    require(scope in ("full-pass", "manual-fixture-only"), "Unknown evidence scope.")
    require(paths, "At least one explicit QA report is required.")
    require(len(set(path.resolve() for path in paths)) == len(paths), "Duplicate QA report path.")
    if scope == "full-pass":
        require(len(paths) == 1, "Full-pass scope requires one successful full report.")
    registered = set(qa.NONFOCUS + qa.WINDOW)
    requested_union, snapshots, evidence, performance_failures = set(), [], [], []
    reports, module_contract = [], None
    for path in paths:
        raw = path.read_bytes()
        report = json.loads(raw)
        suite_rows = report.get("suites", [])
        names = [suite["name"] for suite in suite_rows]
        require(len(names) == len(set(names)) and set(names) == registered,
                "Report suite inventory differs from the current runner: " + str(path))
        suites = {suite["name"]: suite for suite in suite_rows}
        requested = {name for name, suite in suites.items() if suite.get("status") != "not_requested"}
        require(requested, "Report did not request any suites: " + str(path))
        coverage = report.get("coverage")
        require(coverage in ("full_registered_suite", "selected_suites", "non_focus_suites"),
                "Unknown QA coverage: " + str(path))
        if coverage == "full_registered_suite":
            require(requested == registered, "Full report omitted registered suites: " + str(path))
        if coverage == "non_focus_suites":
            require(requested == set(qa.NONFOCUS), "Non-focus report has the wrong suite set: " + str(path))
        snapshot = qa.input_snapshot(sorted(requested))
        require(report.get("sourceChangedDuringRun") is False and report.get("inputs") == snapshot,
                "QA inputs changed or do not match current requested inputs: " + str(path))
        require(report.get("sourceFingerprint") == fingerprint(snapshot),
                "QA input fingerprint mismatch: " + str(path))
        require(report.get("configuration") == "Release", "Require Release QA: " + str(path))
        distribution = report.get("distribution")
        require(distribution in ("direct", "app-store"), "Unknown distribution: " + str(path))
        require(report.get("compileDefinitions") == qa.compilation_conditions(distribution, "Release"),
                "Wrong compilation conditions: " + str(path))
        require(report.get("target") == qa.TARGET, "QA target differs from the current runner.")
        require(report.get("productionModule", {}).get("status") == "passed",
                "Production module did not compile successfully: " + str(path))
        contract = {key: report.get(key) for key in
                    ("swiftVersion", "sdkVersion", "target", "configuration", "distribution", "compileDefinitions")}
        require(all(contract[key] for key in ("swiftVersion", "sdkVersion", "target")),
                "Missing compiler, SDK or target identity: " + str(path))
        if module_contract is None:
            module_contract = contract
        require(contract == module_contract, "Reports use different production module configurations.")
        failures = [name for name in requested if suites[name].get("status") != "passed"]
        require(report.get("passedSuites") == len(requested) - len(failures)
                and report.get("failedSuites") == len(failures), "QA counts disagree with suite statuses.")
        require(report.get("status") == ("failed" if failures else "passed"),
                "QA status disagrees with suite statuses.")
        report_hash = hashlib.sha256(raw).hexdigest()
        for name in sorted(requested):
            suite = suites[name]
            require(suite.get("compile", {}).get("status") == "passed", "Suite compile did not pass: " + name)
            if suite.get("status") == "passed":
                require(suite.get("exitCode") == 0, "Passing suite does not have a successful exit: " + name)
                continue
            require(scope == "manual-fixture-only" and name == PERFORMANCE_SUITE,
                    "Unresolved functional or full-pass failure: " + name)
            summary = suite.get("reportedSummary", "")
            require(suite.get("status") == "failed" and suite.get("exitCode") == 1
                    and any(message in summary for message in PERFORMANCE_BUDGET_MESSAGES),
                    "Only the explicit 50/33 ms performance-budget failure is permitted; no crashes, timeouts or other assertions.")
            performance_failures.append({"report": str(path.resolve()), "reportSHA256": report_hash,
                                         "suite": name, "status": suite["status"], "exitCode": suite["exitCode"],
                                         "reportedSummary": summary, "log": suite.get("log"),
                                         "testSHA256": snapshot.get("Tests/" + name + ".swift")})
        if scope == "full-pass":
            require(coverage == "full_registered_suite" and not failures,
                    "Full-pass scope requires a successful full registered-suite report.")
        requested_union.update(requested)
        snapshots.append((sorted(requested), snapshot))
        evidence.append({"path": str(path.resolve()), "SHA256": report_hash, "status": report["status"],
                         "coverage": coverage, "requestedSuites": sorted(requested),
                         "startedAtUTC": report.get("startedAtUTC"), "finishedAtUTC": report.get("finishedAtUTC")})
        reports.append(report)
    require("NativeContentDragTests" in requested_union,
            "Current NativeContentDragTests must have a passing requested result.")
    if scope == "manual-fixture-only":
        require(performance_failures, "Manual-fixture-only scope requires explicit retained failed performance-budget evidence.")
    return reports[0], snapshots, {
        "scope": scope, "qaReports": evidence,
        "overallQAStatus": "failed" if scope == "manual-fixture-only" else "passed",
        "releaseAcceptance": False,
        "functionalRequestedSuites": sorted(requested_union - {PERFORMANCE_SUITE}),
        "functionalRequestedPassed": True,
        "unrequestedFunctionalSuites": sorted(registered - requested_union - {PERFORMANCE_SUITE}),
        "failedPerformanceEvidence": performance_failures,
        "evidenceScope": "Only the explicitly requested current functional suites are required/passed; unrequested suites are not covered. This authorizes isolated fixture preparation, not a release or full-application acceptance claim.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, action="append", required=True,
                        help="Current QA report; repeat only for explicit manual-fixture-only scope")
    parser.add_argument("--scope", choices=("full-pass", "manual-fixture-only"), default="full-pass")
    parser.add_argument("--expected-source-fingerprint", required=True)
    parser.add_argument("--prepare", action="store_true",
                        help="Stage and ad-hoc sign copies; never launch the app")
    args = parser.parse_args()
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    production_before = build_inventory()
    require(fingerprint(production_before) == args.expected_source_fingerprint,
            "Current production inventory does not match the coordinator's frozen candidate.")
    report, checked_snapshots, scope_evidence = review_reports(args.report, args.scope)
    distribution = report.get("distribution")
    definitions = qa.compilation_conditions(distribution, "Release")
    module_inputs = {
        "sources": hashes(sources(False)), "compiler": report["swiftVersion"],
        "sdk": report["sdkVersion"], "target": report["target"],
        "configuration": "Release", "distribution": distribution,
        "compileDefinitions": definitions, "runner": sha(NATIVE / "scripts/run_qa.py"),
        "inventory": sha(NATIVE / "scripts/project_inventory.py"),
    }
    cache = NATIVE / "build/qa-cache" / (distribution + "-" + fingerprint(module_inputs))
    library = cache / "libDaBinTestCore.dylib"
    module = cache / "DaBinTestCore.swiftmodule"
    require(qa.cache_valid(cache / "module-ready.json", [library, module], module_inputs),
            "The exact report-derived module cache or its output hashes are invalid.")
    test = NATIVE / "Tests/NativeContentDragTests.swift"
    test_hash = sha(test)
    test_dir = cache / ("NativeContentDragTests-" + test_hash[:16])
    executable = test_dir / "NativeContentDragTests"
    require(qa.cache_valid(test_dir / "executable-ready.json", [executable],
                           {"testSHA256": test_hash, "production": module_inputs}),
            "Current manual test executable/source/cache hash verification failed.")
    require(os.access(executable, os.X_OK), "The verified fixture is not executable.")
    info = plistlib.loads((NATIVE / "Resources/Info.plist").read_bytes())
    result = {
        "checkedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "mode": "prepare" if args.prepare else "verify-only",
        "candidate": {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"]},
        "productionFingerprint": args.expected_source_fingerprint,
        "qaReport": scope_evidence["qaReports"][0]["path"],
        "qaReportSHA256": scope_evidence["qaReports"][0]["SHA256"],
        "distribution": distribution, "module": str(cache), "moduleSHA256": sha(library),
        "fixtureSourceSHA256": test_hash, "cachedExecutable": str(executable),
        "cachedExecutableSHA256": sha(executable), "applicationLaunched": False,
        "fixtureRuntimeScope": "Production nativeContentDrag gesture with fictional NSString/NSURL payloads; no archive-backed exporter or sandbox enforcement. Manual branch has no store/preferences/services/general clipboard access. AppKit may use the unique fixture bundle's own preference domain.",
        **scope_evidence,
    }
    if args.prepare:
        stage = Path(tempfile.mkdtemp(prefix="DaBin-CrossApp-" + info["CFBundleShortVersionString"] + "-", dir="/private/tmp"))
        app = stage / "DaBin Fictional Drag QA.app"
        binary = app / "Contents/MacOS/DaBinFictionalDragQA"
        frameworks = app / "Contents/Frameworks"
        resource_directory = app / "Contents/Resources"
        for directory in (binary.parent, frameworks, resource_directory):
            directory.mkdir(parents=True)
        shutil.copy2(executable, binary)
        bundled_library = frameworks / library.name
        shutil.copy2(library, bundled_library)
        subprocess.run(["/usr/bin/install_name_tool", "-rpath", str(cache),
                        "@executable_path/../Frameworks", str(binary)], check=True)
        for resource in resources():
            shutil.copyfile(resource, resource_directory / resource.name)
        bundle_id = "com.dabin.qa.crossapp." + uuid.uuid4().hex
        app_info = {
            "CFBundleIdentifier": bundle_id, "CFBundleName": "DaBin Fictional Drag QA",
            "CFBundleExecutable": binary.name, "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": info["CFBundleShortVersionString"],
            "CFBundleVersion": info["CFBundleVersion"], "NSPrincipalClass": "NSApplication",
            "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "14.0",
            "LSEnvironment": {"DABIN_NATIVE_DRAG_MANUAL": "1"},
        }
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(app_info))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundled_library)], check=True)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        (stage / "Finder received fictional files").mkdir()
        shutil.copyfile(Path(__file__).with_name("local_drag_receiver.html"), stage / "local-drag-receiver.html")
        result.update(stage=str(stage), application=str(app), bundleIdentifier=bundle_id,
                      stagedExecutableSHA256=sha(binary), stagedLibrarySHA256=sha(bundled_library),
                      explicitLaterOpenCommand=["/usr/bin/open", "-n", str(app), "--args", "--manual"],
                      receiver=str(stage / "local-drag-receiver.html"),
                      finderDestination=str(stage / "Finder received fictional files"))
        receipt_path = stage / "staging-receipt.json"
        result["receipt"] = str(receipt_path)
    require(build_inventory() == production_before
            and all(qa.input_snapshot(selected) == snapshot for selected, snapshot in checked_snapshots),
            "Source changed during verification/preparation; do not launch this fixture.")
    require(all(sha(Path(item["path"])) == item["SHA256"] for item in scope_evidence["qaReports"]),
            "A QA receipt changed during preparation; do not launch this fixture.")
    require(qa.cache_valid(cache / "module-ready.json", [library, module], module_inputs),
            "Module cache changed during preparation; do not launch this fixture.")
    require(qa.cache_valid(test_dir / "executable-ready.json", [executable],
                           {"testSHA256": test_hash, "production": module_inputs}),
            "Cached executable changed during preparation; do not launch this fixture.")
    result["inputsAndCacheUnchanged"] = True
    if args.prepare:
        receipt_path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
