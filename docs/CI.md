# Continuous integration

GitHub Actions is the default CI for Shogun. The optional Jenkinsfile calls the same Python runner, so both systems use identical build, analysis, test, and coverage checks. The app remains offline and does not gain runtime dependencies.

## Checks

The named GitHub check is **iOS build, tests and coverage**. It runs on pull requests into dev/main, pushes to those branches, and manual dispatch. Superseded runs on the same ref are cancelled.

The pipeline:

1. Logs the Xcode version and selected iOS runtime/device, then creates a dedicated iPhone simulator.
2. Checks whitespace and runs regression tests for the CI report exporter and coverage gate.
3. Compiles/runs the existing standalone model checks.
4. Builds the app and runs Xcode static analysis for Simulator. Swift/Clang compiler warnings are errors; signing is disabled.
5. Runs the entire shared Shogun XCTest scheme with coverage enabled and parallel simulator testing disabled.
6. Exports the xcresult bundle, JUnit XML, coverage JSON, Sonar generic coverage XML, and a readable summary. A failed test, unexpected skipped test, empty test run, missing core coverage, or coverage regression fails CI.
7. Shuts down and deletes only the simulator created by this run.

The hosted runner is **macos-15**, with **Xcode 16.4** explicitly selected through DEVELOPER_DIR. The compatible installed iOS runtime is selected at execution time (normally iOS 18.5 on this Xcode image), preferring iPhone 16. Local/Jenkins validation supports Xcode 16.4 or later; CI logs record the actual versions. The initial local verification uses Xcode 27 / iOS 27; hosted Xcode 16.4 still needs a real GitHub run. Review runner-image changes rather than silently moving to macos-latest.

No signing team, certificate, provisioning profile, API credentials, or live application backend is required. This workflow does not archive an installable IPA or deploy to TestFlight/App Store.

## Coverage policy

`ci/coverage-policy.json` preserves the existing 100% executable-line baseline for CatalogStore.swift and Models.swift. Missing files or a zero-line report fail instead of passing an empty check. Views, services, mocks, and other app Swift sources remain visible in the overall report and Sonar coverage; UI files are not excluded to improve the percentage.

These core thresholds do not mean 100% whole-app coverage. Line coverage also does not establish branch coverage, rendered layout, two-finger gesture recognition, blank-space hit testing, VoiceOver behavior, or navigation suppression. Continue the ticket's device acceptance checks. As more business logic is added, add appropriate tests and extend the policy deliberately.

The exporter rejects failed, empty, skipped, or inconsistent test results and preserves JUnit/diagnostic artifacts on test failures where Xcode produced a readable bundle. If Xcode cannot launch tests or generate coverage, the pipeline fails and retains the available logs; a missing bundle is not a successful run.

## Run locally

From the repository root, with full Xcode selected and an installed iOS simulator runtime:

```sh
python3 scripts/ci/run.py
```

Results are written to `build/ci/` (Git-ignored). Choose a fresh directory for subsequent local runs, because Xcode refuses an existing result bundle:

```sh
python3 scripts/ci/run.py --output /tmp/shogun-ci-next
```

To select a specific installed runtime, set CI_SIMULATOR_RUNTIME to its identifier or pass `--runtime`. The runner creates its own device and does not erase or shut down your existing simulator. Do not run it against a directory containing important files.

Export or recheck an existing xcresult bundle independently:

```sh
python3 scripts/ci/reports.py /absolute/path/Tests.xcresult --output build/ci
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
```

For reports produced elsewhere, source paths must correspond to this checkout; use `--root` to specify the original checkout path. The resulting Sonar report uses repository-relative paths so it can be uploaded from another CI step.

## Artifacts and diagnostics

GitHub retains logs, JSON/XML reports, summary.md, and the complete Tests.xcresult for 14 days, even when validation fails. DerivedData is not uploaded. Open the downloaded xcresult bundle in Xcode to inspect test failures, diagnostics, and coverage. The workflow summary shows source coverage when report export completes.

If the job fails early, inspect xcode-version.log, runtimes.log, simulator logs, model-checks.log, build-analyze.log, and xctest.log as available. Install a compatible runtime if selection fails. The simulator creation and cleanup IDs are logged. Cancelled jobs are best-effort cleanup; on persistent Jenkins agents, remove only abandoned devices named Shogun CI after confirming no build owns them.

Structured Xcode/simulator output is parsed directly from command stdout; diagnostic logs are not read back as configuration. Stderr stays separate from structured stdout, and simulator lifecycle commands accept a validated canonical UUID.

GitHub-hosted macOS runners consume Actions capacity and can incur charges depending on repository visibility, plan, and usage. The workflow has a 35-minute timeout, avoids duplicate obsolete runs, and limits artifact retention. Jenkins requires an available Mac agent and its operating cost. See the current [GitHub billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions) rather than assuming a free allowance.

## SonarQube Cloud activation

Sonar integration is implemented but inactive until configured. It requires an existing SonarQube Cloud project and organization with a plan that supports the repository's visibility and desired branch/PR analysis. Sonar computes analysis findings and imports coverage produced by Xcode; it does not run XCTest itself.

1. Create/import this GitHub repository in SonarQube Cloud. Confirm that source upload to that organization is intended. Choose CI-based analysis instead of automatic analysis so Xcode coverage is imported.
2. Add the project analysis token as the repository Actions **secret** `SONAR_TOKEN`. Do not put it in a file, workflow argument, or app configuration.
3. Set repository Actions **variables** `SONAR_PROJECT_KEY` and `SONAR_ORGANIZATION` to the exact existing keys. Then set `SONAR_ENABLED` to `true`.
4. Run the workflow. Enabling Sonar without all required settings fails the configuration step. When disabled, the summary explicitly says analysis did not run; tests/core coverage still execute.
5. Confirm coverage imports and PR decoration in Sonar. The scanner waits up to five minutes for the configured Sonar quality gate and fails if it does not pass. Review the project's new-code definition and quality gate before making it a required MR check.

Sonar credentials are not supplied to fork pull requests. The workflow uses pull_request, not pull_request_target, and has only contents:read permission. Source checkout credentials are not persisted. Official checkout, artifact, and Sonar scan actions are pinned to immutable commits, with Dependabot configured to propose Actions updates into dev.

Sonar settings live in sonar-project.properties; no project/organization keys are invented. The hosted integration targets https://sonarcloud.io. Self-hosted SonarQube is an alternative but Swift analysis requires a suitable commercial edition; it is not installed or configured by this change.

## Jenkins support

The repository includes a Declarative Jenkinsfile, not a Jenkins server installation. Configure a Multibranch Pipeline pointing to this repository and use an isolated trusted Mac agent labelled **macos** and **xcode**, with full Xcode 16.4+, Python 3, and an installed iOS simulator runtime. Select Xcode on the agent or set DEVELOPER_DIR in its environment. The job requires the Pipeline, Git, GitHub Branch Source, Credentials Binding, and JUnit plugins.

Build/test/coverage needs no app secrets. The pipeline starts from a clean dedicated Jenkins workspace, checks out the triggering revision, and publishes JUnit results plus logs and xcresult artifacts even after failures. Configure branch/PR discovery and GitHub webhook/status integration in Jenkins; those server settings cannot be activated by a repository Jenkinsfile alone.

Optional Jenkins Sonar analysis is disabled by default. To enable it:

- Install the official SonarScanner CLI and its required Java runtime on the trusted agent.
- Create a scoped Jenkins secret-text credential with ID `shogun-sonar-token`.
- Set RUN_SONAR and the exact SONAR_PROJECT_KEY/SONAR_ORGANIZATION job parameters.
- Analysis runs only for trusted dev/main branch builds, never change-request builds. Keep Sonar credentials unavailable to untrusted jobs/agents through Jenkins credential scope and branch trust configuration. A guard inside an editable Jenkinsfile alone cannot secure an untrusted job with credential access.

Prefer one Sonar publisher (GitHub Actions by default) so Jenkins does not submit duplicate analyses for the same revision. The Jenkinsfile itself still needs validation against your Jenkins controller/plugin versions; no Jenkins host or credentials were supplied in this task.

## Rollout and acceptance

SHO-13 stays In Development until the repository changes are reviewed and the hosted systems are verified. After approval, push an MR into dev and confirm:

- The named check starts automatically; updates cancel/restart the correct run.
- Build, static analysis, XCTest, standalone checks, and coverage pass on the pinned hosted toolchain.
- A temporary deliberately failing test in a disposable branch makes the check fail and exposes diagnostics. Remove that test before merge. Local exporter regression tests already verify failed tests/coverage cannot become a green report.
- Manual dispatch works after the workflow is present on the repository's default branch.
- Sonar configuration, report import, and quality-gate failures work after activation; fork PRs receive no token.
- Jenkins indexing/webhooks, Mac agent execution, and JUnit/artifact publishing work if Jenkins is used.

Branch-protection changes are a separate decision; no required checks or merge policies are modified here. SHO-2 is independently in MR #7 and is not copied into this branch; CI runs whatever test suite exists on the revision under test.

## References

- [GitHub macOS runner software inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [Official SonarSource Swift coverage example](https://github.com/SonarSource/sonar-scanning-examples/tree/master/swift-coverage)
- [Official Sonar scan action](https://github.com/SonarSource/sonarqube-scan-action)
- [Jenkinsfile documentation](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/)
