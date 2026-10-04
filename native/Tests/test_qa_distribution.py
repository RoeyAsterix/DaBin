"""Runner command/report regressions; mock compilation and every native launch."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_qa


class QADistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dabin-qa-runner-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Sources/DaBin/Fixture.swift"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("struct Fixture {}\n")
        test = self.root / "Tests/SoftwareUpdateTests.swift"
        test.parent.mkdir()
        test.write_text("// Fictional compile input; never compiled or executed.\n")
        inventory = self.root / "scripts/project_inventory.py"
        inventory.parent.mkdir()
        inventory.write_text("# Fictional inventory\n")
        self.commands = []

    def operation(self, arguments, log, timeout):
        command = [str(value) for value in arguments]
        self.commands.append(command)
        if "-o" in command:
            Path(command[command.index("-o") + 1]).write_bytes(b"synthetic compile output")
        if "-emit-module-path" in command:
            Path(command[command.index("-emit-module-path") + 1]).write_bytes(b"synthetic module")
        log.write_text("PASS: mocked runner plumbing only\n")
        return {"status": "passed", "exitCode": 0, "seconds": 0,
                "log": str(log.relative_to(self.root))}

    def run_channel(self, *arguments):
        with mock.patch.object(run_qa, "ROOT", self.root), \
             mock.patch.object(run_qa, "sources", return_value=[self.source]), \
             mock.patch.object(run_qa, "resources", return_value=[]), \
             mock.patch.object(run_qa, "hashes", return_value={"Sources/DaBin/Fixture.swift": "fixture"}), \
             mock.patch.object(run_qa, "input_snapshot", return_value={"fixture": "unchanged"}), \
             mock.patch.object(run_qa, "capture", return_value="fixture toolchain"), \
             mock.patch.object(run_qa, "operation", side_effect=self.operation), \
             mock.patch.object(run_qa.os, "chdir"), \
             mock.patch.object(sys, "argv", ["run_qa.py", "--only", "SoftwareUpdateTests", *arguments]), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_qa.main(), 0)
        return json.loads((self.root / "build/qa/latest-run.json").read_text())

    @staticmethod
    def conditions(command):
        return [command[index + 1] for index, argument in enumerate(command[:-1]) if argument == "-D"]

    def assert_compile_conditions(self, expected):
        commands = [command for command in self.commands if command[:2] == ["xcrun", "swiftc"]]
        self.assertEqual(len(commands), 2, "Production module and test wrapper must both be compiled")
        self.assertTrue(any("-emit-library" in command for command in commands))
        self.assertTrue(any("-lDaBinTestCore" in command for command in commands))
        for command in commands:
            self.assertEqual(self.conditions(command), expected)

    def test_default_stays_direct_for_production_and_test_wrapper(self):
        report = self.run_channel()
        self.assert_compile_conditions(["DABIN_DIRECT_UPDATES"])
        self.assertEqual(report["distribution"], "direct")
        self.assertEqual(report["compileDefinitions"], ["DABIN_DIRECT_UPDATES"])
        self.assertTrue((self.root / "build/qa/latest-run-direct.json").is_file())

    def test_store_release_omits_direct_flag_from_both_compiles(self):
        report = self.run_channel("--distribution", "app-store")
        self.assert_compile_conditions([])
        self.assertEqual(report["distribution"], "app-store")
        self.assertEqual(report["compileDefinitions"], [])
        self.assertIn("no distribution signing", report["runtimeScope"])
        self.assertTrue((self.root / "build/qa/latest-run-app-store.json").is_file())

    def test_store_debug_keeps_debug_without_enabling_direct_updates(self):
        report = self.run_channel("--distribution", "app-store", "--configuration", "Debug")
        self.assert_compile_conditions(["DEBUG"])
        self.assertEqual(report["compileDefinitions"], ["DEBUG"])

    def test_channel_cache_and_latest_reports_cannot_reuse_each_other(self):
        direct = self.run_channel("--distribution", "direct")
        self.commands.clear()
        store = self.run_channel("--distribution", "app-store")
        self.assert_compile_conditions([])
        caches = list((self.root / "build/qa-cache").iterdir())
        self.assertEqual(len(caches), 2)
        self.assertEqual({path.name.split("-", 1)[0] for path in caches}, {"app", "direct"})
        for cache in caches:
            saved = json.loads((cache / "module-ready.json").read_text())
            distribution = saved["inputs"]["distribution"]
            self.assertTrue(cache.name.startswith(distribution + "-"))
            self.assertEqual(saved["inputs"]["compileDefinitions"],
                             ["DABIN_DIRECT_UPDATES"] if distribution == "direct" else [])
        self.assertEqual(json.loads((self.root / "build/qa/latest-run-direct.json").read_text()), direct)
        self.assertEqual(json.loads((self.root / "build/qa/latest-run-app-store.json").read_text()), store)
        reports = list((self.root / "build/qa/runs").glob("*/report.json"))
        self.assertEqual(len(reports), 2)
        self.assertEqual({json.loads(path.read_text())["distribution"] for path in reports}, {"direct", "app-store"})

    def test_unknown_channel_or_configuration_is_rejected(self):
        for distribution, configuration in (("store-typo", "Release"), ("direct", "release")):
            with self.subTest(distribution=distribution, configuration=configuration), self.assertRaises(ValueError):
                run_qa.compilation_conditions(distribution, configuration)


if __name__ == "__main__":
    unittest.main()
