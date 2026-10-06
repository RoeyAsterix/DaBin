#!/usr/bin/env python3
"""Run exact old86 writer → explicitly pinned current reader in disposable storage."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NATIVE = REPO / "native"
OLD = NATIVE / "build/store-preparation-20261004/native"
OLD_CACHE = OLD / "build/qa-cache/app-store-34dd658724d8a131934a15dd329a81843c7c8c7af3aad201a34ea2bf28acde4a"
OLD_FINGERPRINT = "cda5504ffbd21b7d090c142f54cf635f8d139adedd61be14a3ab85e045ce62c5"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def verify_inputs(root, values):
    for relative, expected in values.items():
        path = root / relative
        if path.is_symlink() or not path.is_file() or digest(path) != expected:
            raise ValueError(f"Source/input changed: {path}")

def verify_module(root, cache):
    receipt = json.loads((cache / "module-ready.json").read_text())
    inputs = receipt["inputs"]
    if inputs["configuration"] != "Release" or inputs["distribution"] != "app-store":
        raise ValueError("Require Release Store production module")
    actual_inventory = {str(p.relative_to(root)) for p in (root / "Sources/DaBin").glob("*.swift") if p.name != "DaBinMain.swift"}
    if actual_inventory != set(inputs["sources"]):
        raise ValueError(f"Production module inventory differs: {cache}")
    verify_inputs(root, inputs["sources"])
    verify_inputs(cache, receipt["outputs"])
    return receipt

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Compile two small harnesses, then run sequentially; no app build, GUI, signing or network")
    parser.add_argument("--output-directory", type=Path, help="New, absent /private/tmp/DaBin-Upgrade-* directory; default creates one")
    parser.add_argument("--current-module-cache", type=Path, help="Must exactly match the module cache in the released source freeze")
    parser.add_argument("--current-version", help="Must exactly match the version in the released source freeze")
    parser.add_argument("--current-build", help="Must exactly match the build in the released source freeze")
    args = parser.parse_args()
    if not args.run:
        print("Prepared only. Add --run after the native build slot is released.")
        return 0
    frozen = json.loads((HERE / "prepared-inputs.json").read_text())
    if frozen["status"] != "prepared_not_executed":
        raise ValueError("Current source/module freeze is not released; no native execution")
    new_cache = Path(frozen["currentModuleCache"]).resolve()
    if args.current_module_cache and args.current_module_cache.resolve() != new_cache:
        raise ValueError("Requested module differs from the released source freeze")
    current_version = frozen["currentVersion"]
    current_build = str(frozen["currentBuild"])
    if (args.current_version and args.current_version != current_version) or (args.current_build and args.current_build != current_build):
        raise ValueError("Requested version/build differs from the released source freeze")
    if not current_build.isascii() or not current_build.isdigit():
        raise ValueError("Require a numeric pinned build identifier")
    verify_inputs(NATIVE, frozen["currentNativeInputs"])
    verify_inputs(HERE, frozen["qaInputs"])
    old_candidate = OLD / "build/store-unsigned-0.4.31-86/store-candidate-receipt.json"
    candidate = json.loads(old_candidate.read_text())
    if candidate["sourceFingerprint"] != OLD_FINGERPRINT or str(candidate["buildNumber"]) != "86":
        raise ValueError("Historical uploaded source identity differs")
    verify_inputs(OLD, candidate["inputs"])
    old_module = verify_module(OLD, OLD_CACHE)
    new_module = verify_module(NATIVE, new_cache)
    if digest(new_cache / "module-ready.json") != frozen["currentModuleReceiptSHA256"]:
        raise ValueError("Current module receipt differs from the released freeze")
    info = plistlib.loads((NATIVE / "Resources/Info.plist").read_bytes())
    if (info["CFBundleShortVersionString"], str(info["CFBundleVersion"])) != (current_version, current_build):
        raise ValueError("Current Info.plist differs from the pinned candidate version/build")
    if old_module["inputs"]["compiler"] != new_module["inputs"]["compiler"] or old_module["inputs"]["target"] != new_module["inputs"]["target"]:
        raise ValueError("Cached compiler/target must match")
    if args.output_directory:
        out = args.output_directory.expanduser().absolute()
        if out.parent.resolve() != Path("/private/tmp") or not out.name.startswith("DaBin-Upgrade-") or out.exists() or out.is_symlink():
            raise ValueError("Output must be a new /private/tmp/DaBin-Upgrade-* root")
        out.mkdir(mode=0o700)
    else:
        out = Path(tempfile.mkdtemp(prefix="DaBin-Upgrade-" + current_build + "-", dir="/private/tmp"))
    out = out.resolve()
    token = str(uuid.uuid4())
    (out / "FixtureOwner.json").write_text(json.dumps({"token": token}) + "\n")
    for directory in ["preferences", "tmp", "module-cache", "logs"]:
        (out / directory).mkdir(mode=0o700)
    # Preserve HOME and CODEX_HOME; explicit store URLs define the fixture scope.
    env = dict(os.environ, CFFIXED_USER_HOME=str(out / "preferences"), TMPDIR=str(out / "tmp"),
        DABIN_UPGRADE_FIXTURE_TOKEN=token, DABIN_UPGRADE_CURRENT_IDENTITY=current_version + " (" + current_build + ")")
    env.pop("DYLD_LIBRARY_PATH", None)
    env.pop("DYLD_INSERT_LIBRARIES", None)
    report = {"schemaVersion": 1, "startedAtUTC": now(), "status": "running", "submissionReady": False,
        "scope": "Headless synthetic production-core forward data upgrade. No signed application/TestFlight install, real archive, clipboard, network, preference domains or GUI.",
        "oldSourceFingerprint": OLD_FINGERPRINT, "oldCandidateReceiptSHA256": digest(old_candidate),
        "currentFreezeSHA256": digest(HERE / "prepared-inputs.json"), "fixtureRoot": str(out),
        "currentVersion": current_version, "currentBuild": current_build, "HOMEOverridden": False,
        "moduleReceipts": {"old": str(OLD_CACHE / "module-ready.json"), "new": str(new_cache / "module-ready.json")},
        "moduleReceiptSHA256": {"old": digest(OLD_CACHE / "module-ready.json"), "new": digest(new_cache / "module-ready.json")},
        "moduleOutputSHA256": {"old": old_module["outputs"], "new": new_module["outputs"]},
        "downgradeSupportedAfterCurrentSave": False, "phases": []}
    def save():
        (out / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    def check_freeze():
        verify_inputs(NATIVE, frozen["currentNativeInputs"])
        verify_inputs(HERE, frozen["qaInputs"])
        verify_module(OLD, OLD_CACHE); verify_module(NATIVE, new_cache)
    def run(name, command, timeout=120):
        check_freeze()
        phase = {"name": name, "command": [str(x) for x in command], "startedAtUTC": now(), "log": str(out / "logs" / (name + ".log"))}
        report["phases"].append(phase); save()
        with Path(phase["log"]).open("w") as stream:
            process = subprocess.Popen(phase["command"], cwd=out, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                phase["exitCode"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait()
                phase["exitCode"] = process.returncode; phase["timedOut"] = True
        phase["endedAtUTC"] = now(); phase["logSHA256"] = digest(Path(phase["log"]))
        check_freeze(); save()
        if phase["exitCode"] != 0 or phase.get("timedOut"):
            raise RuntimeError(f"Phase failed: {name}; see {phase['log']}")
    try:
        for label, cache, module in [("old", OLD_CACHE, old_module), ("new", new_cache, new_module)]:
            flags = [flag for definition in module["inputs"].get("compileDefinitions", []) for flag in ("-D", definition)]
            if label == "old": flags += ["-D", "OLD_BUILD"]
            run("compile-" + label, ["xcrun", "swiftc", "-swift-version", "5", "-target", module["inputs"]["target"],
                "-parse-as-library", "-O", "-warnings-as-errors", "-module-cache-path", out / "module-cache", *flags,
                "-I", cache, "-L", cache, "-lDaBinTestCore", "-Xlinker", "-rpath", "-Xlinker", cache,
                HERE / "UpgradeFixture.swift", "-o", out / (label + "-fixture")])
        # Network is denied by an OS sandbox even though no service/request is instantiated.
        sandbox = ["/usr/bin/sandbox-exec", "-p", "(version 1) (allow default) (deny network*)"]
        archive = out / "Archive"
        run("old-write", [*sandbox, out / "old-fixture", "write", archive, out / "old-write.json"])
        shutil.copytree(archive, out / "Old86-backup")
        run("current-upgrade", [*sandbox, out / "new-fixture", "upgrade", archive, out / "current-upgrade.json"])
        run("current-reopen-1", [*sandbox, out / "new-fixture", "reopen", archive, out / "current-reopen-1.json"])
        run("current-reopen-2", [*sandbox, out / "new-fixture", "reopen", archive, out / "current-reopen-2.json"])
        shutil.copytree(archive, out / "Downgrade-probe")
        run("old-downgrade-rejection", [*sandbox, out / "old-fixture", "reject-downgrade", out / "Downgrade-probe", out / "old-downgrade-rejection.json"])
        report["results"] = {name: json.loads((out / (name + ".json")).read_text()) for name in ["old-write", "current-upgrade", "current-reopen-1", "current-reopen-2", "old-downgrade-rejection"]}
        if any(value["status"] != "passed" for value in report["results"].values()):
            raise RuntimeError("A fixture result did not pass")
        report["fixtureExecutableSHA256"] = {label: digest(out / (label + "-fixture")) for label in ["old", "new"]}
        report["expectedSHA256"] = digest(out / "expected.json")
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"; report["error"] = str(error)
    finally:
        report["endedAtUTC"] = now(); save()
    print(out / "report.json")
    return 0 if report["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())
