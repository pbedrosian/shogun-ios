# Real email verification and password reset

Setup runbook for [SHO-26](https://app.notion.com/p/40408c1af1ec8199b90cd09eb6a5f7e2)
with the iOS flows implemented in SHO-19. **Documented, not activated.** Current local
sign-ups skip email confirmation, recovery mail goes to Mailpit, and no external
SMTP account or sending domain has been configured. Keep that development default
until the steps below are completed. Nothing in this guide provisions a service.

## 1. Choose the sender and environment

Choose an SMTP provider and a domain you control, with access to its DNS settings.
Use separate development and production credentials/senders. Record the provider,
account owner, domain, sender address, environment, and where credentials are kept.

Resend is the worked example here, not a purchased or finalized provider choice.
Another SMTP provider works with the same Supabase settings. With Resend:

1. Create the provider account and add a sending domain/subdomain, such as
   `auth.your-domain.example` (replace every `.example` address in this guide).
2. Add the DNS records supplied by the provider and wait for verification. Configure
   SPF/DKIM as instructed, plus a DMARC policy appropriate to your domain. Preserve
   existing email DNS records; do not invent record values or add a second SPF record.
3. Choose a sender on that verified domain, e.g. `no-reply@auth.your-domain.example`,
   with sender name **Shogun**. A real monitored support/reply address is also needed.
4. Create a dedicated sending credential. For Resend SMTP, the username is `resend`
   and the password is the API key. Store the key in a password manager/server secret
   store, never in an iOS xcconfig or a ticket. Disable click tracking on auth links.

[Resend SMTP settings](https://resend.com/docs/send-with-smtp),
[domain verification](https://resend.com/docs/dashboard/domains/introduction), and
[Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

## 2. Choose the URL users can actually reach

Email delivery alone does not make the local backend public.

| Setting | Local phone test | Hosted development / production |
| --- | --- | --- |
| iOS Supabase URL | `http://MAC_LAN_IP:54321` | `https://PROJECT_REF.supabase.co` |
| Auth link origin | `http://MAC_LAN_IP:54321/auth/v1` | Hosted project's HTTPS Auth URL |
| Native callback / allowed redirect | `shogun://auth-callback` | `shogun://auth-callback` |
| Credentials | Local public client key | That hosted project's public client key |

For local testing, Mac and phone must share a reachable network and the Mac must
be running. Do not send localhost links to outside users. Use a hosted development
project for testing away from your Wi-Fi and a separate production project for real
users. Do not expose Docker/Studio ports publicly to solve this.

The app already registers the `shogun` URL scheme and processes PKCE callbacks.
Keep its exact callback on the allowlist; changing it also requires an iOS change.
For this native-only app, Site URL can use `shogun://auth-callback` as the fallback.
If a web fallback is added, configure a real hosted page rather than port 3000.
See [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

## 3. Configure local SMTP only when ready to test it

The CLI runs with `--workdir backend`, so its project-root dotenv file is
`backend/.env`, beside the `supabase/` directory. Root `.env.local` and the iOS
xcconfig are not SMTP credential sources. Start with the server-only template:

```sh
# Repository root. -n preserves an existing file; merge fields manually if it exists.
cp -n backend/.env.example backend/.env
chmod 600 backend/.env
```

Edit `backend/.env` locally. Set `SHOGUN_SMTP_PASSWORD` to the provider credential
and `SHOGUN_AUTH_EXTERNAL_URL` to your Mac's reachable Auth URL, including `/auth/v1`.
The template's IP is an example, not your saved network address. This file is ignored
by Git. [Supabase documents dotenv substitution here](https://supabase.com/docs/guides/local-development/managing-config).

Merge the following into the existing sections of `backend/supabase/config.toml`;
do not append duplicate tables or remove unrelated settings. This is an **opt-in
example**, not the repository's active default:

```toml
[local_smtp]
enabled = false
port = 54324

[auth]
external_url = "env(SHOGUN_AUTH_EXTERNAL_URL)"
site_url = "shogun://auth-callback"
additional_redirect_urls = ["shogun://auth-callback"]

[auth.email]
enable_confirmations = true
double_confirm_changes = true
secure_password_change = true
max_frequency = "60s"

[auth.rate_limit]
email_sent = 30

[auth.email.smtp]
enabled = true
host = "smtp.resend.com"
port = 587
user = "resend"
pass = "env(SHOGUN_SMTP_PASSWORD)"
admin_email = "no-reply@auth.your-domain.example"
sender_name = "Shogun"
```

Port 587 uses STARTTLS for Resend. Substitute your provider's settings if different.
The sample hourly cap is a starting value; check provider quotas and Supabase limits
rather than disabling throttling. The pinned CLI supports `auth.external_url` as
shown in its [Auth configuration source](https://github.com/supabase/cli/blob/v2.122.0/apps/cli-go/pkg/config/auth.go).
Other fields are in the [CLI configuration reference](https://supabase.com/docs/guides/local-development/cli/config).

Restart without resetting data, then configure and rebuild the phone app:

```sh
npm run backend:stop
npm run dev
# Replace this example with your Mac's current LAN IP:
npm run ios:configure -- --host 192.168.1.20
```

Rebuild in Xcode after changing the iOS URL/key. SMTP/confirmation changes alone
need the backend restart, not an iOS rebuild. New messages should now appear in
the provider's delivery dashboard and actual inbox; Mailpit is no longer the sender.
Verify a newly generated link has the configured LAN origin, not `127.0.0.1`.
Do not reuse emails generated before the configuration changed.

## 4. Configure a hosted project for external users

In the selected hosted Supabase project:

1. Apply repository migrations and verify account bootstrap. Deploy `delete-account`
   as documented in [BACKEND.md](BACKEND.md#account-deletion).
2. In Authentication's email/SMTP settings, enable custom SMTP and enter the verified
   sender, host, port, username, and secret. This is separate from local TOML settings;
   editing local files does not configure the hosted project.
3. Enable the email/password provider and **Confirm email**. Keep secure password
   change and email-change confirmation enabled. Configure sending/request limits
   within your provider's quota; decide abuse/CAPTCHA controls before public signup.
4. Set Site URL/fallback and the exact callback allowlist from section 2. Review
   confirmation and recovery templates, then test both before inviting real users.
5. Put the hosted HTTPS URL and its public key in the intended iOS configuration.
   See [AUTH.md](AUTH.md#hosted-and-release-configuration). Never put SMTP or
   service-role credentials there. Rebuild using that environment.

Use [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp) and
[Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits) as the dashboard
reference. Assign someone to monitor failed/bounced mail and credential rotation.

## 5. Preserve verification and recovery links

Start with the default Confirm signup and Reset password templates. If customizing
HTML, keep the action's `{{ .ConfirmationURL }}` intact, for example:

```html
<a href="{{ .ConfirmationURL }}">Confirm your Shogun account</a>
```

Use the same variable with “Reset your password” in the recovery template. Do not
replace it with Site URL or the bare native callback: Auth must validate the action
before redirecting back with a PKCE code. Avoid provider link rewriting. Inbox
security scanners can also consume one-time links; if this occurs, implement and
test an intentional confirmation landing page or OTP flow before using that design.
Neither a web landing page nor manual OTP entry is implemented in this app.
[Supabase template variables and prefetch guidance](https://supabase.com/docs/guides/auth/auth-email-templates).

The app requests its callback through SDK configuration, exchanges the returned
code, and keeps PKCE/recovery state in Keychain. Open the email link on the same
installation that requested it. Reading it in your Mac's browser cannot reset an
account in the phone app. A newer request can invalidate an earlier pending flow;
use the latest email. [PKCE constraints](https://supabase.com/docs/guides/auth/sessions/pkce-flow).

## 6. Acceptance checks before enabling verification for users

Use real inboxes you control in a nonproduction environment. `.test` fixture
addresses cannot receive external mail; fixtures are preconfirmed and do not prove
signup verification. Do not run the Mailpit-specific live recovery test against
external SMTP unchanged—it targets a fixture and expects captured mail.

- [ ] New email signup shows “check your email”; no signed-in account/private data
  is available before confirmation. Correct-password login is rejected meanwhile.
- [ ] Confirmation reaches the actual inbox, sender/domain checks pass, and its
  link opens the original phone app and the correct personal library.
- [ ] Sign out, sign in, and relaunch preserve the expected authenticated identity.
- [ ] Forgot password reaches that inbox. The link opens **Reset password**, allows
  a successful new password, and returns to the account. After sign-out, the old
  password fails and the new password works.
- [ ] Relaunch during recovery preserves the reset screen; cancel safely signs out.
- [ ] Unknown-email recovery gives the same generic UI message, without creating
  an account or revealing whether it exists.
- [ ] Expired, used, wrong-installation and superseded links fail safely; requesting
  a fresh link recovers. Repeat in light/dark appearance and on a physical phone.
- [ ] Provider delivery failures and throttling are diagnosable without logging
  passwords, JWTs, PKCE codes, complete action links, or SMTP credentials.
- [ ] Add and test an explicit **Resend confirmation** action with cooldown before
  public rollout. That button is not implemented yet; recovery can already be retried.

Record environment, build, tester, date, and pass/fail evidence. Provider acceptance
is not proof of inbox delivery or successful password update. Existing automated
checks cover SDK/state/UI behavior and local Mailpit callbacks; they have not
verified delivery through an external SMTP account.

## Troubleshooting and rollback

| Symptom | Check |
| --- | --- |
| UI says sent; no inbox message | Was a recovery request for a real account? Inspect Auth errors and provider delivery/bounce status, spam, sender verification, quota and suppression lists. Generic recovery UI deliberately does not confirm account existence. |
| Email still appears only in Mailpit | SMTP settings were not activated in this environment or the local stack was not restarted. |
| Link contains localhost / phone cannot connect | Wrong Auth external URL or old email; create a fresh link. For users outside your LAN, use hosted HTTPS. |
| Email opens the wrong page or never opens the app | Check template action URL, allowlisted redirect and installed app scheme; request on that same installation. |
| Link immediately expired | Used/older link, missing PKCE state, scanner prefetch, or link tracking. Do not repeatedly reuse it. |
| Reset opens the library instead of the reset form | Verify the app build's recovery marker handling and that the request started in that installation. Treat as a failed acceptance check. |
| Repeated sends fail | Wait for the configured cooldown and check provider/Auth rate limits; do not turn limits off. |

Local rollback: disable `[auth.email.smtp]`, re-enable `[local_smtp]`, restore the
normal local Auth URL/site settings, and restart. Restore `enable_confirmations =
false` only for the current local development bypass if desired. Preserve data;
no database reset is required. Keep existing unrelated dotenv secrets when editing.

For hosted users, restore known-working SMTP credentials/templates and investigate;
do not use the local confirmation bypass as a production mail-delivery fix.
