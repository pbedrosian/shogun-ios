"""Regression tests for reports that control CI pass/fail and external coverage."""
import unittest
from pathlib import Path
import tempfile
from unittest.mock import patch
import xml.etree.ElementTree as ET

from reports import app_files, coverage_violations, export, junit_report
from run import simulator_configuration


class ReportTests(unittest.TestCase):
    def test_missing_or_zero_coverage_fails_instead_of_passing(self):
        policy = {"Shogun/Models/Models.swift": 1.0}
        self.assertTrue(coverage_violations({}, policy))
        self.assertTrue(coverage_violations({"Shogun/Models/Models.swift": {"executableLines": 0}}, policy))

    def test_coverage_regression_fails_and_exact_threshold_passes(self):
        path = "Shogun/Services/CatalogStore.swift"
        item = {"executableLines": 10, "coveredLines": 9, "lineCoverage": 0.9}
        self.assertTrue(coverage_violations({path: item}, {path: 1.0}))
        self.assertFalse(coverage_violations({path: item}, {path: 0.9}))

    def test_test_target_and_external_generated_files_do_not_inflate_app_coverage(self):
        root = Path("/checkout")
        source = {"path": "/checkout/Shogun/Models/Models.swift"}
        report = {"targets": [{"name": "ShogunTests.xctest", "files": [source]},
                              {"name": "Shogun.app", "files": [source, {"path": "/derived/Generated.swift"}]}]}
        self.assertEqual(app_files(report, root), {"Shogun/Models/Models.swift": source})
        with self.assertRaises(ValueError):
            app_files({"targets": []}, root)

    def test_junit_preserves_failed_and_skipped_results(self):
        children = [{"nodeType": "Test Case", "name": status, "nodeIdentifier": "Suite/" + status,
                     "result": status, "durationInSeconds": 0.1} for status in ["Passed", "Failed", "Skipped", "Unknown"]]
        xml, counts = junit_report({"testNodes": [{"children": children}]})
        self.assertEqual(counts, {"tests": 4, "failures": 2, "skipped": 1})
        self.assertEqual(len(xml.findall("testcase/failure")), 2)
        self.assertEqual(len(xml.findall("testcase/skipped")), 1)

    def test_simulator_selection_ignores_unavailable_and_non_ios_runtimes(self):
        def runtime(version, available=True, platform="iOS"):
            return {"isAvailable": available, "identifier": "com.apple.CoreSimulator.SimRuntime." + platform + "-" + version,
                    "version": version, "supportedDeviceTypes": [{"name": "iPhone 16", "identifier": "phone"}]}
        chosen, device = simulator_configuration({"runtimes": [runtime("18.5"), runtime("27.0", False), runtime("26.0", platform="tvOS")]})
        self.assertEqual(chosen["version"], "18.5")
        self.assertEqual(device["identifier"], "phone")
        with self.assertRaises(ValueError):
            simulator_configuration({"runtimes": []})

    def test_failed_test_exports_diagnostics_but_cannot_pass_the_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = str(root / "Shogun/Models/Models.swift")
            responses = [
                {"result": "Failed", "totalTestCount": 1, "skippedTests": 0},
                {"testNodes": [{"nodeType": "Test Case", "name": "broken", "result": "Failed"}]},
                {"targets": [{"name": "Shogun.app", "files": [
                    {"path": source, "executableLines": 2, "coveredLines": 1, "lineCoverage": 0.5}]}]},
                {source: [{"line": 1, "isExecutable": True, "executionCount": 1},
                          {"line": 2, "isExecutable": True, "executionCount": 0},
                          {"line": 3, "isExecutable": False}]}
            ]
            output = root / "reports"
            with patch("reports.xcode_json", side_effect=responses):
                with self.assertRaisesRegex(ValueError, "XCTest run did not pass"):
                    export(root / "Tests.xcresult", output, root, {"Shogun/Models/Models.swift": 1.0})
            self.assertIsNotNone(ET.parse(output / "junit.xml").find("testcase/failure"))
            lines = ET.parse(output / "sonarqube-coverage.xml").findall("file/lineToCover")
            self.assertEqual([line.attrib["covered"] for line in lines], ["true", "false"])
            self.assertIn("below 100.0%", (output / "summary.md").read_text())


if __name__ == "__main__":
    unittest.main()
