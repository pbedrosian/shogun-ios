# iOS authentication (SHO-19)

The app uses the official Supabase Swift SDK's Auth product, pinned to 2.55.4.
Email/password signup, sign-in, password recovery, persistent sessions and account
deletion are connected. Google sign-in is enabled for Shogun Dev only; Apple and
release social login remain pending. Collection synchronization is connected; see [COLLECTIONS.md](COLLECTIONS.md).

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
buttons first, then a mode-specific “Or log in with” / “Or sign up with” divider,
then the email form in a rounded panel. Signup still reveals password fields only
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
