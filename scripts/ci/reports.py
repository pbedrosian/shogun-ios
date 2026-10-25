#!/usr/bin/env python3
"""Export real Xcode reports and enforce per-file business-logic coverage."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def xcode_json(*args):
    return json.loads(subprocess.check_output(["xcrun", *map(str, args)], text=True))


def app_files(report, root):
    files = {}
    for target in report.get("targets", []):
        if target.get("name") != "Shogun.app":
            continue
        for item in target.get("files", []):
            path = Path(item["path"])
            try:
                relative = path.relative_to(root).as_posix()
            except ValueError:
                continue
            if relative.startswith("apps/ios/Shogun/") and relative.endswith(".swift"):
                files[relative] = item
    if not files:
        raise ValueError("No app source coverage found; refusing to report an empty success.")
    return files


def coverage_violations(files, policy):
    errors = []
    for path, minimum in policy.items():
        if not isinstance(minimum, (int, float)) or not 0 <= minimum <= 1:
            raise ValueError("Coverage thresholds must be numbers from 0 to 1.")
        item = files.get(path)
        if item is None or item.get("executableLines", 0) == 0:
            errors.append(f"{path}: missing executable-line coverage")
        elif item["coveredLines"] / item["executableLines"] < minimum:
            errors.append(f"{path}: {item['lineCoverage']:.1%} is below {minimum:.1%}")
    return errors


def junit_report(tree):
    suite = ET.Element("testsuite", name="Shogun")
    counts = {"tests": 0, "failures": 0, "skipped": 0}

    def visit(node):
        if node.get("nodeType") == "Test Case":
            counts["tests"] += 1
            identifier = node.get("nodeIdentifier", node["name"])
            case = ET.SubElement(suite, "testcase", name=node["name"],
                                 classname=identifier.rsplit("/", 1)[0],
                                 time=str(node.get("durationInSeconds", 0)))
            result = node.get("result", "Unknown")
            if result in ("Skipped", "Not Run"):
                counts["skipped"] += 1
                ET.SubElement(case, "skipped", message=result)
            elif result != "Passed":
                counts["failures"] += 1
                ET.SubElement(case, "failure", message=result).text = json.dumps(node)
        else:
            for child in node.get("children", []):
                visit(child)

    for node in tree.get("testNodes", []):
        visit(node)
    for key, count in counts.items():
        suite.set(key, str(count))
    return suite, counts


def write_xml(element, destination):
    ET.ElementTree(element).write(destination, encoding="utf-8", xml_declaration=True)


def export(bundle, output, root, policy):
    output.mkdir(parents=True, exist_ok=True)
    # Export test results first so failures still reach Jenkins and the artifacts.
    summary = xcode_json("xcresulttool", "get", "test-results", "summary", "--path", bundle)
    tree = xcode_json("xcresulttool", "get", "test-results", "tests", "--path", bundle)
    (output / "test-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (output / "test-tree.json").write_text(json.dumps(tree, indent=2) + "\n")
    junit, counts = junit_report(tree)
    write_xml(junit, output / "junit.xml")
    errors = []
    if counts["tests"] == 0 or summary.get("totalTestCount", 0) == 0:
        errors.append("No tests executed")
    if counts["tests"] != summary.get("totalTestCount"):
        errors.append("Test tree and summary disagree on the number of tests")
    if summary.get("result") != "Passed" or counts["failures"]:
        errors.append("XCTest run did not pass")
    if counts["skipped"] or summary.get("skippedTests", 0):
        errors.append("XCTest unexpectedly skipped tests")

    report = xcode_json("xccov", "view", "--report", "--json", bundle)
    (output / "coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    files = app_files(report, root)
    errors += coverage_violations(files, policy["files"])
    coverage = ET.Element("coverage", version="1")
    for relative, item in sorted(files.items()):
        raw = xcode_json("xccov", "view", "--archive", "--file", item["path"], "--json", bundle)
        lines = raw.get(item["path"])
        if lines is None:
            raise ValueError(f"Missing coverage archive for {relative}")
        element = ET.SubElement(coverage, "file", path=relative)
        for line in lines:
            if line.get("isExecutable"):
                ET.SubElement(element, "lineToCover", lineNumber=str(line["line"]),
                              covered="true" if line.get("executionCount", 0) > 0 else "false")
    write_xml(coverage, output / "sonarqube-coverage.xml")
    covered = sum(item["coveredLines"] for item in files.values())
    executable = sum(item["executableLines"] for item in files.values())
    minimum = policy["minimumAppCoverage"]
    if not isinstance(minimum, (int, float)) or not 0 <= minimum <= 1:
        raise ValueError("App coverage threshold must be a number from 0 to 1.")
    if not executable or covered / executable < minimum:
        errors.append(f"App source coverage {covered / executable if executable else 0:.1%} is below {minimum:.1%}")
    text = ["# Shogun CI", "", f"Tests: {counts['tests']}; failures: {counts['failures']}; skipped: {counts['skipped']}",
            f"App source line coverage: {covered}/{executable} ({covered / executable if executable else 0:.1%}); required: {minimum:.1%}", "",
            "| Source | Covered / executable | Line coverage |", "| --- | --- | --- |"]
    for path, item in sorted(files.items()):
        text.append(f"| {path} | {item['coveredLines']}/{item['executableLines']} | {item['lineCoverage']:.1%} |")
    text += ["", "Line coverage does not establish branch coverage or UI interaction verification.", ""]
    text += [f"FAIL: {error}" for error in errors] if errors else ["Coverage and test checks passed."]
    (output / "summary.md").write_text("\n".join(text) + "\n")
    if errors:
        raise ValueError("; ".join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--output", type=Path, default=Path("build/ci"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        policy = json.loads((root / "ci/coverage-policy.json").read_text())
        export(args.bundle.resolve(), args.output.resolve(), root, policy)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Report/coverage check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
