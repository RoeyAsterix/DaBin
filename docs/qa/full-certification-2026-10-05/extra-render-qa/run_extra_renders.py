#!/usr/bin/env python3
"""Separate, serial compile/render evidence runner; never builds production.

Default: stage and compile only. Runtime requires explicit --run and is owned by
root QA. Exact current production hashes must match module-ready.json before
compilation and before every executable launch. No source or shared-runner edits.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import signal
import subprocess
import sys
import time
import uuid

ACTIVE_REPORT = None
MODULE = "DaBinTestCore"
TARGET = "arm64-apple-macosx14.0"
PRODUCTION_RESOURCES = ["AppIcon.icns", "PrivacyInfo.xcprivacy", "PrivacyPolicy.md", "robot.svg"]
SUITES = [
    {"name": "NativeRenderTests", "mode": "--responsive-detail", "timeoutSeconds": 180,
     "manifest": "responsive-detail-renders.json", "minimumPNGs": 24,
     "scope": "Only the injected-preferences responsive detail branch, before legacy UserDefaults.standard mutation."},
    {"name": "PrivacyRenderTests", "timeoutSeconds": 60, "manifest": "privacy-renders.json", "minimumPNGs": 4,
     "scope": "Real bundled local policy in offscreen non-key windows; no folder button is pressed."},
    {"name": "WalkthroughRenderTests", "timeoutSeconds": 180, "manifest": "walkthrough-renders.json", "minimumPNGs": 25,
     "scope": "Synthetic PDF import/index/search/comment/task/export/archive arc; direct-channel fixture refuses network/installer, App Store branch uses the production inert updater."},
    {"name": "IslandPlaygroundRender", "timeoutSeconds": 180, "manifest": "native-render.json", "minimumPNGs": 2,
     "scope": "Offscreen production character presentation layers, fictional vector desktop, fresh frame sequence; no installed-app recording."},
]
SYNTHETIC_TEXT = """Fictional launch checklist
Synthetic local review fixture
launch checklist: Review the welcome screen.
Confirm the fictional preview layout.
Check readable headings, task planning and local export.
No real customer, project, attachment or personal content is used.
"""


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def current_sources(native):
    return {str(path.relative_to(native)): sha(path) for path in sorted((native / "Sources/DaBin").glob("*.swift"))
            if path.name != "DaBinMain.swift"}


def validate_module(native, module):
    stamp_path = module / "module-ready.json"
    stamp = json.loads(stamp_path.read_text())
    expected = stamp["inputs"]
    current = current_sources(native)
    if not current or current != expected["sources"]:
        mismatches = sorted(key for key in set(current) | set(expected["sources"])
                            if current.get(key) != expected["sources"].get(key))
        raise ValueError("Verified module does not match current production sources: " + ", ".join(mismatches))
    if expected.get("configuration") != "Release" or expected.get("distribution") != "app-store" or expected.get("compileDefinitions") != []:
        raise ValueError("Requires the final App Store Release module with no additional compile definitions")
    if expected.get("target") != TARGET:
        raise ValueError("Module target does not match " + TARGET)
    for name in [f"lib{MODULE}.dylib", f"{MODULE}.swiftmodule"]:
        artifact = module / name
        if not artifact.is_file() or stamp["outputs"].get(name) != sha(artifact):
            raise ValueError("Verified module artifact no longer matches its ready stamp: " + name)
    compiler = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True, stderr=subprocess.STDOUT).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True, stderr=subprocess.STDOUT).strip()
    if compiler != expected.get("compiler") or sdk != expected.get("sdk"):
        raise ValueError("Compiler/SDK changed since module verification")
    return {"moduleReadyStamp": str(stamp_path), "moduleReadyStampSHA256": sha(stamp_path),
            "configuration": "Release", "distribution": "app-store", "compileDefinitions": [], "target": TARGET,
            "compiler": compiler, "sdk": sdk, "productionSources": current, "moduleArtifacts": stamp["outputs"]}


def owned_operation(arguments, cwd, log, timeout, environment=None):
    started = time.monotonic()
    with log.open("w") as output:
        process = subprocess.Popen([str(a) for a in arguments], cwd=cwd, stdout=output,
                                   stderr=subprocess.STDOUT, env=environment, start_new_session=True)
        timed_out = False
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Terminate only the process group launched for this operation.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=3)
            code = process.returncode
    return {"status": "timed_out" if timed_out else "passed" if code == 0 else "failed",
            "exitCode": code, "seconds": round(time.monotonic() - started, 3), "log": str(log),
            "logSHA256": sha(log), "command": [str(a) for a in arguments],
            "shellCommand": shlex.join([str(a) for a in arguments]), "workingDirectory": str(cwd), "timeoutSeconds": timeout}


def artifacts(directory):
    return [{"path": str(path.relative_to(directory)), "bytes": path.stat().st_size, "sha256": sha(path)}
            for path in sorted(directory.rglob("*")) if path.is_file()]


def artifact_check(spec, output):
    manifest_path = output / spec["manifest"]
    if not manifest_path.is_file():
        raise ValueError("Executable exited without its expected render manifest: " + str(manifest_path))
    manifest = json.loads(manifest_path.read_text())
    pngs = list(output.rglob("*.png"))
    if len(pngs) < spec["minimumPNGs"] or any(path.stat().st_size == 0 for path in pngs):
        raise ValueError("Incomplete or empty PNG evidence for " + spec["name"])
    name = spec["name"]
    if name in ["NativeRenderTests", "WalkthroughRenderTests"]:
        for record in manifest["screenshots"]:
            if not (output / record["file"]).is_file():
                raise ValueError("Missing screenshot named by manifest: " + str(record))
        if name == "NativeRenderTests":
            expected = {f"native-view-responsive-{kind}-{mode}-{width}x{height}.png"
                        for mode in ["light", "dark"] for width, height in [(380, 430), (760, 680), (1200, 900), (1200, 430)]
                        for kind in ["image", "task", "comment"]}
            actual = {record["file"] for record in manifest["screenshots"]}
            if actual != expected or len(manifest["screenshots"]) != len(expected):
                raise ValueError("Responsive detail evidence must cover the exact 24 production fixture states")
    elif name == "PrivacyRenderTests":
        for mode in ["light", "dark"]:
            for position in ["top", "bottom"]:
                if not (output / f"privacy-policy-{mode}-{position}.png").is_file():
                    raise ValueError("Missing full-policy reading-position render")
    else:
        if manifest.get("frameCount", 0) <= 0 or len(manifest.get("shots", [])) != 4:
            raise ValueError("Island render lacks its complete four native shots")
        for frame in manifest["frames"]:
            if not (output / frame["file"]).is_file():
                raise ValueError("Missing native animation frame")
    return {"status": "passed", "manifest": str(manifest_path), "manifestSHA256": sha(manifest_path),
            "pngCount": len(pngs), "meaning": "Artifacts and declared checks exist; visual inspection remains separate."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path, default=Path(__file__).resolve().parents[4] / "native")
    parser.add_argument("--module-dir", type=Path, required=True, help="Final verified cache directory containing module-ready.json")
    parser.add_argument("--output-root", type=Path, required=True, help="Creates a fresh named run under this directory")
    parser.add_argument("--run", action="store_true", help="Root only: serial native runtime after compile. Default compiles only.")
    parser.add_argument("--plan-only", action="store_true", help="Validate inputs and prepare wrappers/manifest without compiling or running")
    parser.add_argument("--only", action="append", choices=[s["name"] for s in SUITES])
    args = parser.parse_args()
    if args.plan_only and args.run:
        parser.error("--plan-only and --run cannot be combined")
    native, module = args.native_root.resolve(), args.module_dir.resolve()
    validated = validate_module(native, module)
    selected = [s for s in SUITES if not args.only or s["name"] in args.only]
    selected_names = [s["name"] for s in selected]
    omitted_names = [s["name"] for s in SUITES if s["name"] not in selected_names]
    run = args.output_root.resolve() / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + uuid.uuid4().hex[:8])
    run.mkdir(parents=True, exist_ok=False)
    (run / "logs").mkdir(); (run / "ModuleCache").mkdir()
    staged_native = run / "fixture/native"; staged_native.mkdir(parents=True)
    shutil.copytree(native / "Resources", staged_native / "Resources")
    fixture_text = run / "fixture/fictional-launch-checklist.txt"; fixture_text.write_text(SYNTHETIC_TEXT)
    report = {"schemaVersion": 1, "startedAtUTC": now(), "runner": str(Path(__file__).resolve()),
              "runnerSHA256": sha(Path(__file__).resolve()), "status": "preparing", "runtimeRequested": args.run,
              "nativeRoot": str(native), "moduleDirectory": str(module), "runDirectory": str(run),
              "coverage": {"selection": "partial" if omitted_names else "complete", "selectedSuites": selected_names,
                           "omittedSuites": omitted_names, "availableSuiteCount": len(SUITES),
                           "allStandaloneModesIncluded": not omitted_names,
                           "meaning": "Status applies only to selected suites; omitted suites receive no runtime or artifact claim from this receipt."},
              "verifiedModule": validated, "syntheticFixture": {"path": str(fixture_text), "sha256": sha(fixture_text)},
              "resourceInputs": {str(path.relative_to(native)): sha(path) for path in sorted((native / "Resources").rglob("*")) if path.is_file()},
              "scope": "Standalone native offscreen view/presentation renders and declared model actions; no general clipboard, network, permissions or installed-user-app recording.",
              "limitations": "Render evidence requires separate human inspection. Island sampling timestamps/deadlines are not physical display refresh-rate measurements. Wrappers use the recorded test sources verbatim; the verified production module is unchanged.",
              "suites": []}
    report_path = run / "extra-render-report.json"
    global ACTIVE_REPORT
    ACTIVE_REPORT = report_path
    write_json(report_path, report)
    common = ["xcrun", "swiftc", "-swift-version", "5", "-target", TARGET,
              "-module-cache-path", str(run / "ModuleCache"), "-warnings-as-errors", "-parse-as-library",
              "-O", "-whole-module-optimization", "-I", str(module), "-L", str(module), f"-l{MODULE}",
              "-Xlinker", "-rpath", "-Xlinker", str(module)]
    baseline_info = plistlib.loads((native / "Resources/Info.plist").read_bytes())
    for spec in selected:
        name = spec["name"]; source = native / f"Tests/{name}.swift"
        app = run / "apps" / f"{name}.app"
        contents = app / "Contents"; macos = contents / "MacOS"; resources = contents / "Resources"
        macos.mkdir(parents=True); resources.mkdir()
        for resource in PRODUCTION_RESOURCES:
            shutil.copyfile(native / "Resources" / resource, resources / resource)
        info = dict(baseline_info)
        info.update({"CFBundleExecutable": name, "CFBundleIdentifier": "com.dabin.mac.qa.extra." + name.lower(),
                     "CFBundleName": name, "LSUIElement": True})
        fixture_info_overrides = {}
        if name == "PrivacyRenderTests":
            # This existing fixture explicitly tests the no-public-links scenario.
            # Strip keys only from its disposable bundle, never production Info.
            keys = ["DaBinPrivacyPolicyURL", "DaBinSupportURL"]
            fixture_info_overrides = {"removedKeys": keys,
                "sourceValues": {key: baseline_info.get(key) for key in keys},
                "reason": "Unconfigured public policy/support links fixture; existing native assertion is unchanged."}
            for key in keys: info.pop(key, None)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        wrapper = run / f"fixture/{name}.swift"
        wrapper.write_text(f"@testable import {MODULE}\n" + source.read_text())
        executable = macos / name; output = run / "renders" / name; output.mkdir(parents=True)
        arguments = [str(executable)]
        if name == "NativeRenderTests": arguments.append("--responsive-detail")
        arguments.append(str(output))
        if name == "WalkthroughRenderTests": arguments.append(str(fixture_text))
        compile_command = [*common, str(wrapper), "-o", str(executable)]
        suite = {"name": name, "scope": spec["scope"], "testSource": str(source), "testSourceSHA256": sha(source),
                 "wrapper": str(wrapper), "wrapperSHA256": sha(wrapper), "bundle": str(app),
                 "sourceInfoSHA256": sha(native / "Resources/Info.plist"), "fixtureInfoOverrides": fixture_info_overrides,
                 "bundleInfoSHA256": sha(contents / "Info.plist"), "bundleInfoOverrides": {key: info[key] for key in ["CFBundleExecutable", "CFBundleIdentifier", "CFBundleName", "LSUIElement"]},
                 "compileCommand": compile_command, "runtimeCommand": arguments,
                 "workingDirectory": str(staged_native), "output": str(output), "timeoutSeconds": spec["timeoutSeconds"],
                 "resourceSHA256": {name: sha(resources / name) for name in PRODUCTION_RESOURCES}, "status": "prepared"}
        report["suites"].append(suite); write_json(report_path, report)
        if not args.plan_only:
            # Fail closed before compiling against an obsolete module as well.
            if validate_module(native, module) != validated:
                raise ValueError("Verified module inputs changed after staging")
            suite["compile"] = owned_operation(compile_command, staged_native, run / f"logs/{name}-compile.log", 180)
            suite["status"] = "compiled_not_run" if suite["compile"]["status"] == "passed" else "compile_failed"
            if executable.is_file(): suite["executableSHA256"] = sha(executable)
            write_json(report_path, report)
    if args.run:
        for suite, spec in zip(report["suites"], selected):
            if suite["status"] != "compiled_not_run": continue
            # Both the module ready stamp and every current production source
            # must still match before any GUI executable is started.
            try:
                if validate_module(native, module) != validated:
                    raise ValueError("Module/source inputs changed before runtime")
                for row in report["suites"]:
                    if sha(Path(row["testSource"])) != row["testSourceSHA256"]:
                        raise ValueError("Render source changed after compilation")
                for relative, value in report["resourceInputs"].items():
                    if sha(native / relative) != value: raise ValueError("Production resource changed before runtime")
            except Exception as error:
                report["status"] = "invalidated_before_runtime"; report["validationError"] = str(error)
                write_json(report_path, report); print("BLOCKED:", error, flush=True); return 2
            environment = os.environ.copy()
            environment.update({"DYLD_LIBRARY_PATH": str(module)})
            suite["runtime"] = owned_operation(suite["runtimeCommand"], staged_native,
                run / f"logs/{suite['name']}.log", spec["timeoutSeconds"], environment)
            suite["status"] = suite["runtime"]["status"]
            if suite["status"] == "passed":
                try: suite["artifactCheck"] = artifact_check(spec, Path(suite["output"]))
                except Exception as error: suite["status"] = "artifact_failed"; suite["artifactError"] = str(error)
            suite["artifacts"] = artifacts(Path(suite["output"]))
            write_json(report_path, report)
            print(suite["name"], suite["status"], flush=True)
    report["finishedAtUTC"] = now()
    report["status"] = ("prepared_only" if args.plan_only else "failed" if any(s["status"] in ["compile_failed", "failed", "timed_out", "artifact_failed"] for s in report["suites"])
                        else "passed" if args.run else "compiled_not_run")
    report["sourceChangedDuringRun"] = current_sources(native) != validated["productionSources"]
    if report["sourceChangedDuringRun"]: report["status"] = "invalidated_by_source_changes"
    write_json(report_path, report)
    print("REPORT", report_path, report["status"], flush=True)
    return 0 if report["status"] in ["prepared_only", "compiled_not_run", "passed"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        if ACTIVE_REPORT is not None and ACTIVE_REPORT.is_file():
            failed = json.loads(ACTIVE_REPORT.read_text())
            failed.update({"status": "runner_failed", "runnerError": str(error), "finishedAtUTC": now()})
            write_json(ACTIVE_REPORT, failed)
        print("Extra render preparation failed:", error, file=sys.stderr)
        sys.exit(2)
