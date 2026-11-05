# Keys, ids and files: where to get each one

Everything goes into `secrets/master.env` (git-ignored). Lines that still need you say `#TODO: ADD THE INFO`. A sign-in
method whose lines are empty is simply switched off (its button disappears from `/login`). After editing, send the
file to the machines: `scripts/push-secrets.sh user@host` (it also sends `*.p8` and `apple-domain.txt`), then restart.

Your domain below is `parshwa.blog`; the website is `game.parshwa.blog` and the master is `api-game.parshwa.blog`.

| You get | Goes in `master.env` |
|---|---|
| Discord client id / secret / bot token | `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN` |
| Google client id / secret | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` |
| Apple Services ID, Team ID, Key ID, `.p8`, domain file | `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_FILE`, `APPLE_DOMAIN_FILE` |
| Resend API key | `RESEND_API_KEY` (+ `RESEND_EVENT`) |

Never paste these into chat, an issue or a commit. If one leaks, make a new one in the same console and delete the old.

## Discord (login, and password/username codes by DM)

1. https://discord.com/developers/applications > **New Application** (name Rysteria).
2. **OAuth2** page: copy **Client ID** → `DISCORD_CLIENT_ID`; **Reset Secret** → `DISCORD_CLIENT_SECRET`.
   Under **Redirects** add exactly `https://api-game.parshwa.blog/oauth/discord/callback`.
3. **Bot** page: **Reset Token** → `DISCORD_BOT_TOKEN`. (It only messages people who share a Discord server with the
   bot and allow DMs from server members.)
4. Invite the bot to your server: OAuth2 > URL Generator > scope `bot`, no permissions.

## Google (sign in with Google)

1. https://console.cloud.google.com > create a project (e.g. Rysteria).
2. **APIs & Services > OAuth consent screen** (Google Auth Platform > Branding): app name `Rysteria`, support email,
   **App logo** `https://game.parshwa.blog/logo-120.png` (download it and upload the file, 120x120), **Application
   home page** `https://game.parshwa.blog/`, **Privacy policy** `https://game.parshwa.blog/privacy`, **Terms of
   service** `https://game.parshwa.blog/terms` (both pages are served by the website, see `rrolf/Client/public/`),
   **Authorized domains** `parshwa.blog`, a developer contact. Google asks you to **verify the domain** once in
   Search Console (https://search.google.com/search-console, add `parshwa.blog` as a domain property and put the TXT
   record it shows in Cloudflare DNS). Audience **External**. Scopes are only the basic
   ones (`openid`, `email`, `profile`). Then **Publish app** (otherwise only listed test users can sign in, and
   the login expires after 7 days).
3. **Credentials > Create credentials > OAuth client ID**, type **Web application**. Under **Authorized redirect URIs**
   add exactly `https://api-game.parshwa.blog/oauth/google/callback`. (No JavaScript origins are needed.)
4. Copy the **Client ID** and **Client secret** → `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.

The Android and iOS apps use this same client: they open Google in the system browser, not in the web view.

## Apple (Sign in with Apple, needed by the App Store when other social logins exist)

Needs the paid Apple Developer Program (https://developer.apple.com/programs/enroll/). All of this is in
https://developer.apple.com/account > *Certificates, Identifiers & Profiles*.

1. **Team ID** → `APPLE_TEAM_ID`: *Membership details* page, 10 characters.
2. **Primary App ID**: *Identifiers > + > App IDs > App*, bundle id `blog.parshwa.rysteria`, tick **Sign in with Apple**.
   (This is the same id the iOS app uses.)
3. **Services ID** = the web client: *Identifiers > + > Services IDs*, identifier e.g. `blog.parshwa.rysteria.web`
   → this is `APPLE_CLIENT_ID`. Open it, tick **Sign in with Apple > Configure**: Primary App ID = the one from step 2,
   **Domains** `api-game.parshwa.blog` (no `https://`), **Return URLs**
   `https://api-game.parshwa.blog/oauth/apple/callback`.
4. **Domain verification**: only if that dialog shows a **Download** link for a verification file (newer dialogs do not,
   then skip this step). If it does: save the file as `secrets/apple-domain.txt`, set
   `APPLE_DOMAIN_FILE=~/.rysteria-secrets/apple-domain.txt`, push the secrets, restart the master (it serves the file at
   `https://api-game.parshwa.blog/.well-known/apple-developer-domain-association.txt`) and press **Verify** the same day,
   Apple's file expires after a few days.
5. **Server-to-server notification endpoint** (in the same Services ID dialog, or under the primary App ID's
   *Sign in with Apple > Edit*): `https://api-game.parshwa.blog/oauth/apple/notify`. Apple posts a signed message there when a
   person revokes the app or deletes their Apple Account. The master accepts only messages that carry Apple's signature
   (checked against Apple's published keys), are addressed to this app and are recent; everything else gets a bare 401.
   Each genuine notice is mailed to `ADMIN_EMAIL`, even when the daily email limit is used up.
6. **Email sources** (so the codes reach people who chose "Hide My Email"): *Certificates, Identifiers & Profiles >
   Services > Configure Sign in with Apple for Email Communication*: Domain `email.parshwa.blog`, address
   `noreply@email.parshwa.blog`. Needs the SES DKIM records below. Details in [`APPLE.md`](APPLE.md), step 1d.
7. **Key**: *Keys > +*, name Rysteria, tick **Sign in with Apple > Configure** → pick the primary App ID → Save →
   Continue → Register. **Download the `.p8` now (only once)** into `secrets/` (e.g. `secrets/apple.p8`);
   the **Key ID** on that page → `APPLE_KEY_ID`; `APPLE_PRIVATE_KEY_FILE=~/.rysteria-secrets/apple.p8`.

## Resend (the emails: confirm address, password and username codes)

The master calls Resend's events API (`POST https://api.resend.com/events/send`) with
`{"event": RESEND_EVENT, "email": <recipient>, "payload": {"subject", "text", "OTP"}}`. Resend then runs the
**automation** that starts on that event, so the sender address and the layout are set there, not in the master.

1. https://resend.com > **API Keys > Create API Key** with permission **Full access** (a "Sending access" key is
   refused by this endpoint with `restricted_api_key`). Copy it → `RESEND_API_KEY`.
2. **Domains**: add and verify your sending domain (the DNS records go into Cloudflare, DNS only).
3. **Automations > Create**: trigger = event `OTP SEND` (the value of `RESEND_EVENT`), step = **Send email** from
   an address on the verified domain; subject `{{{subject}}}`, body `{{{text}}}` (the payload fields; `OTP` holds
   just the code if you want to lay it out yourself, empty for mails that have none). Set it live.
4. `RESEND_EVENT=OTP SEND`. The master sends at most `EMAIL_DAILY_LIMIT` (50) emails a day.

## Already set up on your side

Cloudflare tunnel (`common.env`), the database, `SERVER_SECRET`, `TOKEN_SECRET_*`, `OTP_PEPPER`, `MINIGAMES_PIN` and
`CLONE_SECRET` (the last four are random strings you can regenerate with `openssl rand -hex 32`; changing the
token secrets logs everybody out).

For the phone apps (Android keystore, Apple team and App Store Connect key, store accounts) see
[`scripts-phones/README.md`](scripts-phones/README.md).
