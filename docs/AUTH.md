# iOS authentication (SHO-19)

The app uses the official Supabase Swift SDK's Auth product, pinned to 2.55.4.
Email/password signup, sign-in, password recovery, persistent sessions and account
deletion are connected. Google and native Apple sign-in are enabled for Shogun Dev;
real Apple consent/linking/revocation acceptance is pending. Release social login
remains disabled. Collection synchronization is connected; see [COLLECTIONS.md](COLLECTIONS.md).

For actual inbox delivery, domain/SMTP configuration, email confirmation and full
reset acceptance checks, follow [EMAIL.md](EMAIL.md). Hosted alpha has custom SMTP and confirmed device acceptance; see the validation
record below. Local confirmation remains disabled and recovery mail uses Mailpit.

## Simulator startup

From the repository root:

```sh
npm ci
npm run dev
npm run backend:fixtures
```

Open `apps/ios/Shogun.xcodeproj`, choose Shogun and an installed iPhone simulator,
and Run. Xcode resolves the pinned Swift package on the first build.

The app opens directly to Sign in with the SHOGUN wordmark. Create account requires
matching passwords of at least 8 characters. Local signup currently signs in
immediately; a hosted project with confirmation enabled returns a check-email
message until its link is followed. Forgot password opens recovery.

Existing fixture identities/passwords are documented in [BACKEND.md](BACKEND.md).
The signed-in account opens its saved default or accessible personal library and
loads real collection data. The sample catalog is restricted to Debug UI-test launch arguments;
there is no offline/demo entry point in the normal app.

## Local configuration and physical iPhone

The launcher creates ignored `apps/ios/Configuration/Local.xcconfig` only if missing,
using the running local project's public key and simulator URL. Regenerate it with:

```sh
npm run ios:configure
```

For a physical phone, use your Mac's current private LAN IP instead of loopback:

```sh
# Example only; replace with your Mac's address.
npm run ios:configure -- --host 192.168.1.20
```

Choose the phone/signing team in Xcode and rebuild. Keep Mac and phone on the same
Wi-Fi and allow local network access. Debug supports local HTTP; Release accepts
only HTTPS and has no local-network ATS exception. An unconfigured build explains
setup and disables submission. Existing local config is preserved by the launcher.

Current local recovery messages are captured at `http://127.0.0.1:54324` on the Mac,
or `http://MAC_LAN_IP:54324` from the phone. Open the action on the installation that
requested it. If the captured verification URL contains loopback, replace only its
host with the Mac LAN IP for this local test. EMAIL.md documents configuring the
Auth external URL correctly so newly sent emails need no manual repair.

## Side-by-side development app

Debug installs as **Shogun Dev**, bundle `com.petebedrosian.shogun.dev`, with callback
`shogun-dev://auth-callback`. Release retains the alpha identity
`com.petebedrosian.shogun` and `shogun://auth-callback`. Keychain storage is scoped
to the app bundle identifier, so the installations keep independent sessions.
Allow both exact callback URLs in hosted Auth redirect settings before testing
Dev confirmation/recovery or OAuth. Local Supabase configuration includes both.

Debug can use the existing hosted alpha project through its ignored Local.xcconfig.
Use a separate test account and test library: separate installations do not isolate
server data when signed in as the same user. Hosted provider/settings changes affect
both installations. Do not reset or migrate alpha data for development testing.
Run Debug directly from Xcode; do not upload it under the alpha App Store record.

## Hosted and release configuration

Debug optionally includes ignored `Configuration/Local.xcconfig`; Release includes
ignored `Release.local.xcconfig` instead. Use a hosted project's HTTPS URL/public
key in the intended file. Avoid xcconfig's `//` comment parsing with this spelling:

```xcconfig
SUPABASE_URL = https:/$()/YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_YOUR_PUBLIC_CLIENT_KEY
```

Rebuild after URL/key changes. The app accepts a publishable or legacy anon key,
and rejects secret/service-role keys. Apply migrations and deploy the delete-account
function before shipping. Allow `shogun://auth-callback` in the project's Auth redirect
settings. No hosted project or provider credential is provisioned by this guide.
Server SMTP credentials belong in the backend/provider settings, never these files.

### Validated hosted configuration helper (SHO-26)

Alpha uses email/password. Apple and Google sign-in exploration is tracked in SHO-32.
Configure a verified sending domain and custom SMTP before external signup/recovery
acceptance. Keep provider credentials in hosted Auth settings, never in iOS config.

Supply `SHOGUN_HOSTED_SUPABASE_URL` and `SHOGUN_HOSTED_PUBLISHABLE_KEY` in your
terminal environment using the selected project's HTTPS URL and **public** client
key, then run:

```sh
npm run ios:configure:hosted -- --configuration debug
# Only when intentionally replacing the existing Debug endpoint:
npm run ios:configure:hosted -- --configuration debug --replace
# Prepare Release separately, when its environment is ready:
npm run ios:configure:hosted -- --configuration release
```

The helper accepts standard `https://PROJECT_REF.supabase.co` URLs, rejects server
keys and malformed/injected settings, and checks project identity on legacy anon
keys. Modern publishable keys are opaque; connectivity still needs verification
against the selected project. It writes only the selected ignored xcconfig, with
owner-only permissions, and refuses overwrite without `--replace`. It prints no
key or URL. No project is created, database migrated, or app rebuilt by this command.
Custom Supabase domains require a separately reviewed configuration path.

Before applying hosted changes, record project ownership, region, service tier,
existing data/migration state, and backup/recovery arrangements. Authenticate the
Supabase CLI locally with `npx supabase login`; do not paste its access token into
chat or put it in iOS configuration. Inspect hosted migration history before
planning a push, and deploy the catalog and delete-account functions with their
required server secrets. Keep the existing local collection intact.

### Hosted alpha validation — October 29, 2026

The hosted backend has the application migrations and `catalog` / `delete-account`
functions deployed. The narrowly scoped config in
`backend/hosted/alpha/supabase/config.toml` was applied using an explicit project
reference. It enables confirmations, allows `shogun://auth-callback`, replaces the
localhost site URL with that callback, and enables secure password changes.
A subsequent config diff reported zero declared updates; undeclared remote
settings were preserved. Never push the local development config to hosted alpha.

Disposable-account hosted API checks passed:

- Unconfirmed password login rejected; signup confirmation token accepted.
- Native callback retained in generated links; password sign-in and refresh work.
- Personal library provisioning and cross-account library isolation work.
- Recovery token permits a password change; old password and token replay fail.
- Anonymous private-table access and invalid-session function requests rejected.
- Authenticated catalog search works; deletion requires the correct password and
  deleted accounts cannot sign in. Disposable test accounts were removed.
- RLS enabled on all seven public application tables; 22 policies present.

API recovery/confirmation tests used administrative generated links without
sending mail. Separately, custom Resend SMTP was configured with a verified sending
domain. A signed Debug build targeting hosted alpha was installed on a physical
iPhone; signup confirmation email delivery, account confirmation, and password
reset were confirmed on that device.

Debug was deliberately switched to hosted alpha after backing up the local
configuration. Release settings were left unchanged. The local collection was
backed up and migrated separately, with movie/copy fields and account-scoped reads
verified; private backups and account data are not part of this repository.
All 23 backend tooling tests passed. No release candidate or final tag was cut.

## Sessions and recovery

Device-bound Keychain storage holds SDK sessions, PKCE verifier and recovery state,
namespaced by backend URL. Password fields clear after requests/navigation. SDK
logging is disabled and errors use fixed safe messages. Do not log request bodies,
passwords, tokens or complete email links.

Relaunch restores/refreshes the session, validates the user with Auth, and loads the
personal library through RLS. Failed restoration offers retry/sign-in. Sign-out
clears private UI and local session state before remote revocation; offline errors
do not restore the local session. Issued JWT expiry remains a server concern.

Recovery exchanges the callback code and opens Reset password. The app preserves
its recovery marker across relaunch until update/cancel. Request and open links in
the same installation; use a fresh link after expiry or a superseding request.

## Profile and account deletion

Profile uses the shared avatar/email/status header, the real personal library and
app version. Delete account requires final destructive confirmation. Email accounts
verify the current password. Google-linked accounts in Dev can reauthenticate using
the same Google account; a different selection is rejected before deletion. The
proof uses an isolated, memory-only Supabase client and never replaces the main
session. Cancelling Google's sheet or a rejected proof leaves the account signed in.
Success clears local session state and returns to sign-in.

The server validates the main session and password or fresh independent OAuth
proof, then hard-deletes that Auth user. Cascades
remove profile/activity/preferences and owned libraries, including shared libraries,
and their copies/memberships. Other accounts and shared movie metadata are retained.
See [backend deletion details](BACKEND.md#account-deletion) for deployment and tests.
The enabled password provider is supported; future social login needs its own
reauthentication flow.

## Validation commands

Docker-independent tooling checks and full simulator validation:

```sh
npm run backend:test
python3 scripts/ci/run.py --output build/auth-validation
```

With local Supabase running, real deletion/cascade checks use temporary accounts:

```sh
npm run backend:test:deletion
```

The SDK/Keychain/Mailpit live checks are opt-in. Generate a **simulator** configuration
first; these checks require exactly the local loopback backend and fixture users.
Use a simulator UDID from `xcrun simctl list devices`:

```sh
xcodebuild -project apps/ios/Shogun.xcodeproj -scheme Shogun \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- SHOGUN_TEST_CONDITIONS=SHOGUN_LIVE_AUTH \
  -only-testing:ShogunTests/LiveAuthTests test
```

The live UI check uses the same signed command with
`-only-testing:ShogunUITests/AuthFlowTests/testLiveLocalSignInRelaunchAndSignOut`.
The recovery integration check expects Mailpit and preserves the fixture password
by verifying rejection of its reuse. It is not an external-inbox test. Ordinary CI
injects in-memory storage and a Debug-only UI service; normal launches use real Auth.

## Google sign-in in Shogun Dev (SHO-32)

The Debug app uses Supabase's official PKCE OAuth flow in an ephemeral system
ASWebAuthenticationSession. Only `openid email profile` are requested. Callback
scope is validated before code exchange; cancelling the request dismisses the
sheet and clears any partial session. Successful login validates the user and
runs the existing account bootstrap, retaining an existing user's library.

The Google Cloud web OAuth client redirects only to the hosted project's
`/auth/v1/callback`; Supabase then redirects to `shogun-dev://auth-callback`.
Keep the generated client secret exclusively in hosted Google provider settings.
The project is in External testing mode. Google's test-user allowlist does not
restrict basic `openid email profile` sign-in; another Google account can create
its own Shogun account. Treat Supabase authorization/RLS as the data-access boundary,
not Google's testing list. No billing account or paid service is needed for this
configuration. See [Google's testing exception](https://support.google.com/cloud/answer/15549945).

Debug's `ShogunGoogleSignInEnabled` plist flag controls presentation. Release
forces the feature off regardless of a plist override. Do not enable release
social login until Apple/equivalent login, explicit account linking, social-only
account deletion and provider revocation have been implemented and verified.
Same-email Google authentication may automatically link to the existing confirmed
email/password user; a forwarding alias is not itself a Google account.

The top social row uses Google's unmodified pre-approved light circular iOS icon
button assets and Apple's official padded logo-only PDF in a white circular button.
Both have mode-specific accessibility labels. Source: https://developers.google.com/identity/branding-guidelines
(https://developers.google.com/static/identity/images/signin-assets.zip).


## Local Apple sign-in implementation (SHO-32)

Native AuthenticationServices authorization is implemented behind the Debug-only
`ShogunAppleSignInEnabled` flag, which defaults to false. Release always disables
Apple presentation. The custom Apple logo-only button appears on sign-in and signup and is absent
from password recovery. Only email is requested;
the app does not require a first-authorization name or merge users by email.

Each attempt creates separate 256-bit random nonce and state values with Security.
Apple receives the SHA-256 nonce; the returned state must match before the identity
token and raw nonce are exchanged through the official Supabase Auth SDK. Supabase
validates the Apple token signature, audience and nonce. Account routing uses the
existing validated-user/bootstrap path and Keychain session storage. The proof and
challenge stay in memory and are discarded after completion/cancellation; they are
never logged or placed in app configuration. Cancellation dismisses the native
controller and uses the existing store cancellation/session-cleanup path.

Apple authentication stays disabled in normal Dev/Release builds. Dev now shows a
disabled, dimmed Apple button for layout review, independently of the authentication
flag; Release ignores this preview and keeps the button absent. The service/store
authentication guard remains off, so the preview cannot launch Apple authorization.

For validation: local SDK tests intercept all Auth HTTP
traffic, and `-shogun-auth-ui -shogun-auth-apple` uses a deterministic fixture, not
Apple or hosted Auth. These tests do not establish live Apple consent, private-relay
email behavior, Apple revocation, or real device acceptance.

Peter confirmed on November 12, 2026 that hosted changes must wait for the approved
main/final-tag release. No Apple portal capability, provisioning profile, hosted
provider, deployment or phone installation is changed by this implementation.
At that approved stage:

1. Enable Sign in with Apple for the chosen App IDs and decide Dev/release App ID
   grouping before linking real identities. Add `com.apple.developer.applesignin`
   with the `Default` array value to signing entitlements and regenerate the profiles.
2. Configure the exact native bundle-ID audiences in Supabase's Apple provider;
   preserve nonce verification. Native ID-token sign-in does not require embedding
   a client secret in the app. Keep any server revocation credentials server-only.
3. Finish explicit provider linking and server-side Apple token revocation/account
   deletion before enabling real Apple account creation. Do not treat the existing
   Google-only deletion proof as an Apple deletion implementation.
4. Enable the Debug flag only against the approved configured environment, then
   verify disposable-account consent/cancellation, returning sign-in, private relay,
   relaunch/sign-out, unchanged user/library IDs, revoked consent and account deletion
   on device. Release presentation stays off until these requirements pass.

References: [Supabase native Swift token exchange](https://supabase.com/docs/reference/swift/auth-signinwithidtoken),
[Apple authentication](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple),
[Supabase Apple configuration](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple).


### Social-first authentication layout

At Peter's request on November 12, 2026, sign-in and signup present circular provider
buttons beside a matching circular email selector. Sign-in and signup initially
hide email fields and their submit action; selecting email reveals the form and a
mode-specific “Or log in with” / “Or sign up with” divider in the rounded panel.
The email selection remains active when switching between login and signup;
provider sign-in clears hidden passwords. Signup still reveals password fields only
after a valid email. Recovery stays email-only; no divider appears if no provider
is available. Apple authentication remains gated as described above; Dev can show its disabled preview. Buttons use
48-point targets, explicit VoiceOver labels, official unmodified artwork and equal
prominence. Apple logo-only vector padding is preserved; the Google icon asset
includes its approved circular boundary. White provider buttons remain visible in
both appearances. Peter explicitly approved Apple's Developer Artwork License for
Sign in with Apple before extracting its logo resources.

Artwork: [Apple Design Resources](https://developer.apple.com/design/resources/),
[Apple custom button guidance](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/),
[Google branding guidelines](https://developers.google.com/identity/branding-guidelines).


## Apple account management and signing preparation

Native Apple linking and deletion are implemented locally behind the Debug-only
`ShogunAppleAccountManagementEnabled` flag (enabled for approved alpha testing). This flag controls the
Profile linking action and Apple deletion support; Release forces it off. The
separate `ShogunAppleSignInEnabled` flag is also enabled in Debug. Release forces
both off. Dev signing requires the entitlement/profile setup described below.

While signed in, Profile asks for explicit confirmation before using the SDK's
`linkIdentityWithIdToken` endpoint. The request carries the existing authenticated
session, not an email-based merge. Both the returned session and the Auth-verified
user must retain the current user UUID; the store also preserves the current
library ID. Cancellation and ordinary linking failure retain the main account.
A cancellation after the server accepts a link can require restoration to reconcile
the displayed provider state. Conflicting identities are not moved between users.
Manual identity linking must be enabled in the approved Supabase Auth environment
before live acceptance; this is enabled under the shared-alpha exception below.

Apple deletion prefers fresh native authorization through an isolated memory-only
Auth client. It sends a one-time Apple authorization code, the expected native
client ID and a distinct same-user Supabase OAuth proof to the server. The server
validates both Supabase tokens online, checks identity/session/freshness, exchanges
the code directly with Apple and binds Apple's returned subject to the authenticated
user's Apple identity. It revokes the returned Apple token before deleting the
Shogun account. Failed revocation preserves the account; temporary proof sessions
are cleaned up. A failure after successful revocation can require renewed Apple
consent before a retry. Codes, Apple tokens and the generated client secret stay
in memory; none are logged or returned to the app.

If Apple confirmation is unavailable, the user can explicitly choose the Shogun
password fallback. The server reauthenticates the current user's password and
returns `apple_revocation_required: true` after deletion. The app clearly instructs
the user to remove Shogun's Apple access manually, both before confirmation and
after success; it never claims automatic revocation in this path. The ordinary
password/Google payload cannot implicitly bypass Apple handling. The deletion
screen also provides a user-initiated support-email route when neither credential
is accessible. Live acceptance must cover unavailable/revoked Apple credentials
and the support deletion process, not only successful native consent.

### Signing opt-in

`Configuration/AppleSignIn.entitlements` contains only the Apple sign-in capability.
Debug leaves `CODE_SIGN_ENTITLEMENTS` empty by default so current signing continues
to work. After the App ID/profile setup is approved and complete, add this to the
private `Configuration/Local.xcconfig` (or pass it as an Xcode build-setting override):

```xcconfig
SHOGUN_APPLE_SIGN_IN_ENTITLEMENTS = Configuration/AppleSignIn.entitlements
```

The Dev audience is `com.petebedrosian.shogun.dev`; the release audience is
`com.petebedrosian.shogun`. Decide Apple primary/grouped App IDs before the first
real identity is linked, then regenerate the matching provisioning profile.
On November 12, 2026, the release App ID was verified with Sign in with Apple
enabled as the primary. The explicit Dev App ID was registered and grouped under
it. The Development profile `Shogun Dev Apple Sign In` was generated using the
existing development certificate and registered device, then installed in Xcode's
local provisioning-profile directory. Its Apple sign-in entitlement is `Default`.
The private Dev configuration opts into the entitlement above; standard automatic
signing selects a compatible Xcode-managed profile without provisioning updates.
The clean signed Dev build was verified with the Apple entitlement in both its
signature and embedded profile, then installed on the registered iPhone.
Release signing remains unchanged. No Apple server key has been created, and
hosted provider configuration remains gated to the approved release except for
Peter's November 12 shared-alpha Apple-testing exception (see below).

### Shared-alpha testing exception

On November 12, Peter chose to retain `shogun-alpha` instead of creating a second
Dev backend and accepted the narrow pre-release Apple-testing exception. Use
separate test accounts; preserve the existing 1.0.0 account and library. Release
flags stay off, and this exception does not authorize unrelated deployments.

The updated `delete-account` function was deployed as version 2. All 35 backend
checks passed, and hosted smoke checks rejected missing/invalid authentication.
The saved version-1 rollback source matches tag `1.0.0`; an ignored local rollback
copy is in `build/alpha-delete-account-rollback`. To restore that source if needed:

```sh
npx supabase --workdir build/alpha-delete-account-rollback functions deploy delete-account --project-ref dxiwdblobeqyzxjktois --use-api --no-verify-jwt
```

The function continues to validate sessions online itself; gateway JWT verification
remains unchanged. Never roll back Apple deletion support while Apple-linked users
still depend on it without first arranging a supported deletion path.

The 1.0.0 password request/response contract remains supported for accounts without
Apple linked. Apple-linked accounts require the newer explicit Apple deletion or
fallback flow; keep them separate from the 1.0.0 testing account. No hosted account
was created or deleted for the smoke checks, and schema/catalog were unchanged.
Peter registered and downloaded the Apple key, then explicitly authorized its
transfer to `shogun-alpha` server-only secrets. The four stored secret hashes were
verified without exposing values; the temporary transfer file was removed. Apple
provider and server client allowlists contain only `com.petebedrosian.shogun.dev`.
Explicit manual linking is enabled; email confirmation remains on and anonymous
sign-in remains off. Native-only login leaves the OAuth secret field blank; the
private key is stored in Edge Function secrets for revocation, never in that field
or in the app. Dev login/account-management flags are now on for device testing.

At the approved release setup, add the release client audience after reviewing
the environment and enabling Release signing/presentation. Retain nonce
verification. The deletion function uses
server-only `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (PKCS#8 P-256 `.p8`)
and comma-separated `APPLE_CLIENT_IDS` with only approved native audiences. It
creates short-lived ES256 client-secret JWTs per attempt. Never put the private
key or generated client secret in iOS configuration, Git or Notion. Native ID-token
sign-in itself does not embed an Apple client secret in the app.

Validation commands include `npm run backend:test:apple-deletion` and the retained
`backend:test:google-deletion` command. Both use the shared local OAuth fixture;
real GoTrue-issued JWTs and local data cascades are exercised, while Apple's
exchange/revocation endpoints are mocked with ephemeral test signing keys. These
checks do not establish real Apple consent or revocation. Live flags are enabled
only for the approved Dev/alpha acceptance; Release remains disabled until that
acceptance and release approval are complete.

References: [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking),
[Apple signing setup](https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple),
[Apple token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens),
[Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).
