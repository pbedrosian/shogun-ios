#!/usr/bin/env python3
"""Shared unsigned iOS validation for GitHub Actions, Jenkins, and local runs."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
from uuid import UUID

from reports import export

ROOT = Path(__file__).resolve().parents[2]


def command(args, output, name, timeout=1200, check=True, capture=False):
    log = output / f"{name}.log"
    print(f"{name}: {' '.join(map(str, args))}", flush=True)
    with log.open("w") as stream:
        if capture:
            # Consume structured stdout directly. Logs are diagnostics, never input.
            result = subprocess.run(list(map(str, args)), cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=stream, text=True, timeout=timeout)
            stream.write(result.stdout)
        else:
            result = subprocess.run(list(map(str, args)), cwd=ROOT, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-40:]), flush=True)
        if check:
            raise subprocess.CalledProcessError(result.returncode, args)
    return result.stdout if capture else result.returncode


def simulator_id(value):
    """Only a canonical UUID may be passed to simulator lifecycle commands."""
    # Xcode destination matching expects CoreSimulator's uppercase representation.
    return str(UUID(value.strip())).upper()


def simulator_configuration(runtimes, requested=None):
    available = [runtime for runtime in runtimes["runtimes"]
                 if runtime.get("isAvailable") and runtime.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    if requested:
        available = [runtime for runtime in available if runtime["identifier"] == requested]
    if not available:
        raise ValueError("No compatible installed iOS simulator runtime. Install one in Xcode Settings > Components.")
    runtime = max(available, key=lambda item: tuple(int(n) for n in item["version"].split(".")))
    devices = [device for device in runtime.get("supportedDeviceTypes", [])
               if device.get("productFamily") == "iPhone" or device.get("name", "").startswith("iPhone")]
    if not devices:
        raise ValueError("Selected iOS runtime has no supported iPhone device types.")
    device = next((device for device in devices if device["name"] == "iPhone 16"), devices[0])
    return runtime, device


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ci")
    parser.add_argument("--runtime", default=os.environ.get("CI_SIMULATOR_RUNTIME"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bundle = output / "Tests.xcresult"
    if bundle.exists():
        parser.error(f"{bundle} already exists. Choose a fresh --output directory.")
    simulator = None

    def interrupted(signum, frame):
        raise InterruptedError(f"CI interrupted by signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        version_output = command(["xcodebuild", "-version"], output, "xcode-version", timeout=30, capture=True)
        version = version_output.splitlines()[0].split()[1]
        if tuple(int(part) for part in version.split(".")) < (16, 4):
            raise ValueError("CI report export requires Xcode 16.4 or later.")
        runtimes_output = command(["xcrun", "simctl", "list", "runtimes", "-j"], output, "runtimes", timeout=30, capture=True)
        runtime, device = simulator_configuration(json.loads(runtimes_output), args.runtime)
        created = command(["xcrun", "simctl", "create", "Shogun CI", device["identifier"], runtime["identifier"]], output, "simulator-create", timeout=60, capture=True)
        simulator = simulator_id(created)
        (output / "environment.json").write_text(json.dumps({"xcode": version, "runtime": runtime["name"],
                                                            "device": device["name"], "udid": simulator}, indent=2) + "\n")
        command(["xcrun", "simctl", "boot", simulator], output, "simulator-boot", timeout=60)
        command(["xcrun", "simctl", "bootstatus", simulator, "-b"], output, "simulator-ready", timeout=180)
        command(["git", "diff", "--check"], output, "whitespace", timeout=30)
        command(["python3", "-m", "unittest", "discover", "-s", "scripts/ci", "-p", "test_*.py"], output, "ci-tool-tests", timeout=60)
        command(["xcrun", "swiftc", "-module-cache-path", output / "ModuleCache",
                 "apps/ios/Shogun/Models/Models.swift", "apps/ios/Shogun/Services/MockCatalog.swift",
                 "apps/ios/Shogun/Services/CatalogStore.swift", "apps/ios/Checks/main.swift", "-o", output / "model-checks"], output, "model-compile")
        command([output / "model-checks"], output, "model-checks", timeout=60)
        common = ["xcodebuild", "-project", "apps/ios/Shogun.xcodeproj", "-scheme", "Shogun",
                  "-derivedDataPath", output / "DerivedData", "CODE_SIGNING_ALLOWED=NO"]
        command(common + ["-destination", "generic/platform=iOS Simulator", "build", "analyze"], output, "build-analyze")
        status = command(common + ["-destination", f"platform=iOS Simulator,id={simulator}",
                                   "-resultBundlePath", bundle, "-enableCodeCoverage", "YES",
                                   "-parallel-testing-enabled", "NO", "test"], output, "xctest", check=False)
        # Export diagnostic artifacts even when XCTest fails; never turn a failed run green.
        export(bundle, output, ROOT, json.loads((ROOT / "ci/coverage-policy.json").read_text()))
        if status:
            raise ValueError(f"xcodebuild test failed with exit code {status}")
        print((output / "summary.md").read_text(), flush=True)
        return 0
    except (OSError, ValueError, InterruptedError, subprocess.SubprocessError) as error:
        print(f"CI failed: {error}. Diagnostics: {output}", file=sys.stderr)
        return 1
    finally:
        if simulator:
            for action in ("shutdown", "delete"):
                try:
                    command(["xcrun", "simctl", action, simulator], output, f"simulator-{action}", timeout=60, check=False)
                except (OSError, subprocess.SubprocessError) as error:
                    print(f"Simulator cleanup failed: {error}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
