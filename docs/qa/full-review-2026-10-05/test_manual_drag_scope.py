"""Offline receipt-gate regressions. No native program, signing or GUI runs."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).with_name("stage_manual_drag.py")
SPEC = importlib.util.spec_from_file_location("manual_drag_stager", PATH)
stager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stager)
NATIVE = "NativeContentDragTests"
FUNCTIONAL = "ProjectWorkspaceViewTests"
PERFORMANCE = stager.PERFORMANCE_SUITE
ALL = [NATIVE, FUNCTIONAL, PERFORMANCE]


def snapshot(selected):
    return {"Sources/DaBin/Fixture.swift": "production-current", "Resources/PrivacyPolicy.md": "policy-current",
            **{"Tests/" + name + ".swift": "current-" + name for name in selected}}


def report(requested=ALL, failures=(), coverage="full_registered_suite"):
    inputs = snapshot(requested)
    suites = []
    for name in ALL:
        if name not in requested:
            suites.append({"name": name, "status": "not_requested"})
            continue
        failed = name in failures
        suites.append({"name": name, "status": "failed" if failed else "passed", "exitCode": 1 if failed else 0,
                       "compile": {"status": "passed"},
                       "reportedSummary": stager.PERFORMANCE_BUDGET_MESSAGES[0] + " /fictional/performance" if name == PERFORMANCE and failed else "PASS"})
    return {"status": "failed" if failures else "passed", "coverage": coverage, "suites": suites,
            "inputs": inputs, "sourceFingerprint": stager.fingerprint(inputs), "sourceChangedDuringRun": False,
            "configuration": "Release", "distribution": "direct", "compileDefinitions": ["DABIN_DIRECT_UPDATES"],
            "target": stager.qa.TARGET, "swiftVersion": "fixture-compiler", "sdkVersion": "fixture-sdk",
            "productionModule": {"status": "passed"}, "passedSuites": len(requested) - len(failures),
            "failedSuites": len(failures)}


class ManualDragScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="DaBin-ReceiptGate-")
        self.root = Path(self.temporary.name)
        self.patch = patch.multiple(stager.qa, NONFOCUS=[], WINDOW=ALL, input_snapshot=snapshot)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.temporary.cleanup()

    def check(self, reports, scope="manual-fixture-only"):
        paths = []
        for index, value in enumerate(reports):
            path = self.root / (str(index) + ".json")
            path.write_text(json.dumps(value))
            paths.append(path)
        return stager.review_reports(paths, scope)[2]

    def test_default_full_pass_stays_strict(self):
        result = self.check([report()], "full-pass")
        self.assertEqual(result["overallQAStatus"], "passed")
        self.assertFalse(result["releaseAcceptance"])
        with self.assertRaises(SystemExit):
            self.check([report(failures=[PERFORMANCE])], "full-pass")
        with self.assertRaises(SystemExit):
            self.check([report(requested=[NATIVE], coverage="selected_suites")], "full-pass")

    def test_explicit_scope_retains_failed_performance(self):
        original = report(failures=[PERFORMANCE])
        saved = copy.deepcopy(original)
        result = self.check([original])
        self.assertEqual(original, saved)
        self.assertEqual(result["overallQAStatus"], "failed")
        self.assertFalse(result["releaseAcceptance"])
        self.assertEqual(result["functionalRequestedSuites"], sorted([NATIVE, FUNCTIONAL]))
        self.assertEqual(result["failedPerformanceEvidence"][0]["suite"], PERFORMANCE)

    def test_multiple_current_selected_receipts(self):
        result = self.check([report([NATIVE, FUNCTIONAL], coverage="selected_suites"),
                             report([PERFORMANCE], [PERFORMANCE], "selected_suites")])
        self.assertEqual(len(result["qaReports"]), 2)
        self.assertEqual(result["unrequestedFunctionalSuites"], [])

    def test_unrequested_does_not_count_as_passed(self):
        result = self.check([report([NATIVE, PERFORMANCE], [PERFORMANCE], "selected_suites")])
        self.assertEqual(result["functionalRequestedSuites"], [NATIVE])
        self.assertEqual(result["unrequestedFunctionalSuites"], [FUNCTIONAL])

    def test_functional_failure_is_not_waived_or_superseded(self):
        failed = report(failures=[FUNCTIONAL, PERFORMANCE])
        with self.assertRaises(SystemExit):
            self.check([failed])
        with self.assertRaises(SystemExit):
            self.check([failed, report([FUNCTIONAL], coverage="selected_suites")])

    def test_missing_native_drag_result_rejected(self):
        with self.assertRaises(SystemExit):
            self.check([report([FUNCTIONAL, PERFORMANCE], [PERFORMANCE], "selected_suites")])

    def test_changed_inputs_and_resources_rejected(self):
        for key in ("Tests/" + NATIVE + ".swift", "Resources/PrivacyPolicy.md", "Sources/DaBin/Fixture.swift"):
            value = report(failures=[PERFORMANCE])
            value["inputs"][key] = "stale"
            value["sourceFingerprint"] = stager.fingerprint(value["inputs"])
            with self.assertRaises(SystemExit):
                self.check([value])

    def test_source_changed_during_run_rejected(self):
        value = report(failures=[PERFORMANCE])
        value["sourceChangedDuringRun"] = True
        with self.assertRaises(SystemExit):
            self.check([value])

    def test_crash_timeout_compile_and_other_assertions_rejected(self):
        changes = [{"exitCode": -11}, {"status": "timed_out", "exitCode": None},
                   {"compile": {"status": "failed"}}, {"reportedSummary": "Archive original bytes differed"}]
        for change in changes:
            value = report(failures=[PERFORMANCE])
            value["suites"][-1].update(change)
            with self.assertRaises(SystemExit):
                self.check([value])

    def test_no_failed_performance_evidence_rejected(self):
        with self.assertRaises(SystemExit):
            self.check([report()])

    def test_mixed_module_configurations_rejected(self):
        functional = report([NATIVE, FUNCTIONAL], coverage="selected_suites")
        performance = report([PERFORMANCE], [PERFORMANCE], "selected_suites")
        performance.update(distribution="app-store", compileDefinitions=[])
        with self.assertRaises(SystemExit):
            self.check([functional, performance])

    def test_mismatched_counts_and_inventory_rejected(self):
        value = report(failures=[PERFORMANCE]); value["passedSuites"] = 3
        with self.assertRaises(SystemExit):
            self.check([value])
        value = report(failures=[PERFORMANCE]); value["suites"].append(value["suites"][0])
        with self.assertRaises(SystemExit):
            self.check([value])

    def test_full_scope_does_not_union_partial_reports(self):
        with self.assertRaises(SystemExit):
            self.check([report([NATIVE], coverage="selected_suites"),
                        report([FUNCTIONAL, PERFORMANCE], coverage="selected_suites")], "full-pass")


if __name__ == "__main__":
    unittest.main(verbosity=2)
