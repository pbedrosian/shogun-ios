# Branches and release versions

`dev` is the GitHub default branch and the base for feature work. `main` holds
released, tested code and requires an MR. The first upcoming release is `1.0.0`;
main remains at its existing `0.2` until that release is approved and promoted.
SHO-26's hosted alpha setup was accepted and merged into dev in PR #28 on
October 30, 2026. The first candidate still requires approval of its exact dev
commit, release scope, build number and target environment before cutting
`release/1.0.0-rc.1`.

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

## Promotion and tag deployment

1. Change only release metadata to the final `1.0.0` display label on the approved
   candidate; assign the appropriate build number and validate that final revision.
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
deployment workflow or signed iOS archive/TestFlight delivery in this repository.
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

SHO-33 prepares version metadata and this workflow. It does not create an RC,
promote main, publish a tag, configure a Release backend, or distribute an app.
Those actions require their own explicit approval and applicable validation.
