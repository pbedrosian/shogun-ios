# Branches and release versions

`dev` is the GitHub default branch and the base for feature work. `main` holds
released, tested code and requires an MR. The first upcoming release is `1.0.0`;
main remains at its existing `0.2` until that release is approved and promoted.
SHO-26's hosted alpha setup was accepted and merged into dev in PR #28 on
October 30, 2026. Each candidate records the approved source commit, release
scope, build number and target environment. The prepared first candidate is `release/1.0.0-rc.1`.

| Stage | Git branch / tag | App display label | Numeric iOS version |
| --- | --- | --- | --- |
| Upcoming development | `dev` and feature branches | `1.0.0-SNAPSHOT` | `1.0.0` |
| Candidate stabilization | `release/1.0.0-rc.1` | `1.0.0-rc.1` | `1.0.0` |
| Promoted release | `main`, immutable tag `1.0.0` | `1.0.0` | `1.0.0` |
| Next development cycle | `dev` | Next agreed version plus `-SNAPSHOT` | That version's numeric base |

Apple bundle versions stay numeric. `Configuration/Version.xcconfig` supplies
`SHOGUN_BASE_VERSION` for `MARKETING_VERSION` and `SHOGUN_DISPLAY_VERSION` for
the About screen. `CURRENT_PROJECT_VERSION` remains the numeric build counter;
use a new build number for each separately uploaded TestFlight/App Store build.
Debug/Release are compiler configurations, not release channels: both use the
branch's explicit version file. Never derive the channel from whichever branch a
build machine happens to have checked out, or put `SNAPSHOT`/`rc` into Apple's
`CFBundleShortVersionString`.

## Feature and candidate flow

1. Create ticket branches from latest dev and merge reviewed changes into dev.
2. Finish SHO-26 and verify the intended alpha environment, migrations, Auth and
   required functions. Review what will ship; unfinished local work is excluded.
3. Freeze an approved dev SHA into `release/1.0.0-rc.1`. Set the display label to
   `1.0.0-rc.1` and record its build number, commit, environment and test evidence.
4. Keep release fixes on ticket branches based on dev, as with other work. Merge
   fixes into dev and apply the same fix to the RC branch, without carrying other
   unfinished features into the frozen release. Validate the resulting candidate.
5. Subsequent candidates use `release/1.0.0-rc.2`, etc., from the stabilized release
   line. Do not recut from moving dev and unintentionally expand release scope.
6. Advance dev to the next agreed SNAPSHOT when its work starts targeting the next
   release. Choose that next version explicitly; do not assume a major/minor bump.

## TestFlight alpha distribution

TestFlight alpha is pre-release iOS distribution from an approved frozen candidate
commit. It does not require promotion to main or a final release tag, and does not
publish an App Store release. Production deployment remains gated by the final tag.
Alpha uses the existing hosted alpha backend; preparing an archive does not deploy
or migrate that backend.

1. Freeze the approved dev commit and set the candidate display label. Keep Apple's
   numeric version `1.0.0`; allocate a new numeric build for each upload. Verify the
   next build number against App Store Connect before uploading.
2. Configure the candidate worktree's ignored `Release.local.xcconfig` with the
   alpha HTTPS URL and public client key using `ios:configure:hosted`. Debug and
   Release are compiler configurations; backend selection is separate. Never copy
   this alpha override into a production archive without an explicit environment
   decision. Preserve other worktrees' configuration and data.
3. Build/test the exact candidate and archive the Release configuration for a
   generic iOS device. Record its source commit, any uncommitted changes, numeric
   version/build, display label, environment and validation. A local archive may
   be prepared for review, but upload only a clean committed candidate revision.
4. Use Xcode Organizer's App Store Connect distribution flow with the authorized
   Apple Developer team, signing assets and matching App Store Connect app record.
   Verify bundle ID, version, build, alpha endpoint and callback scheme in the
   actual archive. Keep archive/export logs and dSYMs outside Git.
5. After explicit upload/distribution approval, upload and wait for processing.
   Resolve compliance questions accurately. Assign the processed build to an
   internal Alpha group first; App Store Connect users are internal testers.
   External testers require the appropriate TestFlight App Review and tester
   information. Creating a group or inviting testers requires authorization.
6. Test installation, signup/confirmation, reset, relaunch/session persistence,
   library/copy writes and catalog access through TestFlight against alpha. Record
   feedback and acceptance. Candidate fixes get new builds; repeat validation.

Official guidance: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/),
and [create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

## Production promotion and tag deployment

1. Set the final `1.0.0` display label on the approved candidate and assign the
   appropriate build number. Select and verify the production backend explicitly;
   the candidate worktree's alpha `Release.local.xcconfig` is not production config.
   Rebuild and validate the final revision and its intended environment. A package
   built against alpha is not a production artifact.
2. Open an MR from the candidate branch into main. Include the exact candidate,
   test results, release notes and deployment/rollback target. Merge only after
   review and explicit release approval.
3. Create annotated tag `1.0.0` on the resulting main merge commit, then push that
   tag after authorization. Confirm the tag resolves to the reviewed main SHA.
   Tags are immutable: never move or reuse a published final version tag.
4. Deploy from that exact tag/SHA. Record the resolved commit and actual deployed
   artifacts/migration versions. Tag creation alone does not deploy anything.
5. Merge the release changes/fixes back into dev as needed, preserving dev's next
   SNAPSHOT label. Future feature branches continue to start from dev.

The current Actions workflows validate branch pushes and MRs. There is no tag
deployment workflow or automated signed iOS archive/TestFlight delivery in this repository.
TestFlight alpha uploads use the candidate workflow above; the final-tag rule below
applies to production deployments.
SHO-26/SHO-27 must establish hosted credentials, migration review, environment
selection and recovery before a tag can be deployed. Connect any deployment
automation to the approved final tag and its resolved SHA; never deploy moving
dev, an arbitrary feature branch, or an RC under the final release name.

An iOS artifact and a Supabase deployment are distinct outputs. Record both if
both are released. Returning the app to an older tag does not automatically undo
database changes; use the reviewed compatible recovery procedure.

## Hotfixes

Start ordinary fixes on ticket branches from dev. If an urgent fix must ship
without the features already on dev, explicitly approve a ticket branch from the
current immutable release tag as an exception to the normal branch base. Keep its
scope to that release, select the patch version and build number, and validate it
as a release candidate. Promote through an MR into main, then create and deploy
only the approved new final tag; never overwrite the previous release tag.

Apply the same fix back to dev and any active candidate that needs it. Resolve
version-file differences explicitly so dev retains its selected SNAPSHOT label
and each candidate keeps its own release identity. Validate the resulting branch;
a released hotfix does not establish that dev contains the fix.

## Release record

For each approved candidate and final release, record the source commit and
resolved tag SHA, numeric version/build, display label, target environment,
validation evidence, release notes, deployment results and rollback procedure.
Use the existing Shogun Notion ticket/release record for decisions and acceptance;
keep implementation and runbook changes in the repository. Never include secrets.

Preparing a candidate does not promote main, publish a final tag, upload to
TestFlight, invite testers or deploy production. Those actions require their own
explicit approval and applicable validation.

## Local preparation of 1.0.0-rc.1

The first alpha candidate starts at accepted dev commit
`8030a9bfb9119653f5b862c7c79aeaad20b715f4`, excluding uncommitted library
preference changes. It uses numeric version `1.0.0`, display label `1.0.0-rc.1`
and provisional build `2`. Confirm build availability in App Store Connect before
uploading; choose a higher number if already used.

The refreshed local signed archive is
`/private/tmp/shogun-rc1-reprovision/Shogun-refreshed.xcarchive`. It was installed
and successfully launched on Peter's iPhone for direct development testing. The
embedded seven-day profile expires November 6, 2026 at 9:14 AM America/New_York.
Reprovision and reinstall when needed. The archive was built before the preparation
commit; rearchive the reviewed committed candidate before a future upload. Release
configuration in this worktree points to hosted alpha through an ignored override.

Local App Store Connect export failed because Xcode reported no associated
App Store Connect provider and no matching iOS App Store provisioning profile for
`com.petebedrosian.shogun`. A successful device archive alone does not establish
TestFlight distribution signing. Sign in to the authorized Developer Program team,
verify the matching App Store Connect app record, and obtain/manage distribution
signing before retrying the export. Do not replace the app identity or use an
unrelated team to bypass this requirement. No package was uploaded.

The local export options at `/private/tmp/shogun-rc1-preparation/ExportOptions.plist`
use `app-store-connect` with destination `export` and preserve the selected build
number. Exporting locally is distinct from authorizing an upload. Actual TestFlight
installation and alpha acceptance remain pending after export and distribution.

TestFlight is deferred at Peter's request; Apple Developer Program enrollment and
App Store Connect setup have not been completed. Continue direct Xcode device
testing for now. No enrollment purchase, TestFlight upload, main promotion or
final release tag is part of this preparation.
