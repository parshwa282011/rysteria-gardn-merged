# Apple: everything to set up, in order

Your Apple Developer team: **Tejashkumar Shah, Team ID `DTAYB9YB9Y`** (already put in `secrets/master.env` as
`APPLE_TEAM_ID` and in `scripts-phones/phones.env` as `IOS_TEAM_ID`; a Team ID is an identifier, not a secret).
The team name is a person's name, so this is an **Individual** membership: everything below works for it, the
App Store shows your own name as the seller.

Apple's pages are renamed now and then; the names below are what they have been called, search the page for the
word in **bold** if one has moved.

## 0. Do NOT request the "Default Browser Entitlement"

The form you pasted is for apps that **are web browsers** and want to be offered in *Settings > Default Browser App*.
Rysteria is not one, and the form's own checkboxes say what Apple tests for: the app handles `http` and `https` links
from other apps, and on launch shows a URL field, search or bookmarks, and opens any page asked for. Rysteria's app
opens one game and nothing else, so you would have to tick boxes that are not true, and a rejected request "delays
the application process". Close that page without submitting. **Nothing in this guide needs that entitlement.**

What you wanted is already how the app works ([`WebScreen.swift`](phones/ios/Rysteria/WebScreen.swift)):

* The game is shown in Apple's own web view (`WKWebView`, the Safari engine).
* **Sign in with Google / Discord / Apple opens in Apple's system browser sheet** (`ASWebAuthenticationSession`,
  Safari with the user's own cookies and passwords) and comes back to the app by the `rysteria://oauth` link.
* **Any other link a player taps opens in their default browser** (`UIApplication.open`), not inside the game.

That is what the App Store means by "uses the system browser where it should". No special permission is needed.

## 1. Accounts and IDs (developer.apple.com/account > Certificates, Identifiers & Profiles)

You are enrolled already (the form shows your team). Check once that **Membership details** says *Active*, and that
the Apple Account has two-factor authentication on (Apple requires it).

### 1a. The App ID (the iOS app's identity)

*Identifiers > + > App IDs > App > Continue.*

| Field | Put |
|---|---|
| Description | `Rysteria` |
| Bundle ID | **Explicit**, `blog.parshwa.rysteria` (the same as `APP_ID` in `phones.env`; it can never change after the app is published) |
| Capabilities | tick **Sign in with Apple** (leave it on *Enable as a primary App ID*) |

*Continue > Register.* Do not tick anything else (no push, no iCloud: the app does not use them).

### 1b. The Services ID (what the website's "Sign in with Apple" uses)

*Identifiers > + > Services IDs > Continue.*

| Field | Put |
|---|---|
| Description | `Rysteria web sign in` |
| Identifier | `blog.parshwa.rysteria.web` (this is `APPLE_CLIENT_ID` in `master.env`) |

*Continue > Register*, then open the new Services ID, tick **Sign in with Apple** and click **Configure**:

| Field | Put |
|---|---|
| Primary App ID | `Rysteria (blog.parshwa.rysteria)` from step 1a |
| Domains and Subdomains | `api-game.parshwa.blog` (no `https://`, no path) |
| Return URLs | `https://api-game.parshwa.blog/oauth/apple/callback` |
| Email Sources for Apple's Private Email Relay Service | leave empty (we send no email to relay addresses) |
| Server-to-Server Notification Endpoint | `https://api-game.parshwa.blog/oauth/apple/notify` |

**Domain verification file.** Older versions of this dialog had a **Download** link next to the domain and asked you to
host a file. If yours shows no such link (yours did not), there is nothing to do: skip it, leave `APPLE_DOMAIN_FILE`
empty in `master.env`. Only if Apple ever shows the link: download the file, save it as `secrets/apple-domain.txt`,
set `APPLE_DOMAIN_FILE=~/.rysteria-secrets/apple-domain.txt`, push the secrets, restart the master (it serves the
file at `https://api-game.parshwa.blog/.well-known/apple-developer-domain-association.txt`), press **Verify**.
Then *Next > Done > Continue > Save*.

The notification endpoint field exists in the same dialog (and under the primary App ID's *Sign in with Apple >
Edit*). Apple may send a test notification when you save: the master answers 401 to anything that is not
signed by Apple, which is right.

### 1c. The Sign in with Apple key (what lets the master prove itself to Apple)

*Keys > + (Create a key).*

| Field | Put |
|---|---|
| Key Name | `Rysteria sign in` |
| Capabilities | tick **Sign in with Apple > Configure**, pick the primary App ID from 1a > Save |

*Continue > Register > Download.* **You can download the `.p8` only once**: save it as `secrets/apple.p8`
(git-ignored), back it up somewhere private. The page shows the **Key ID** (10 characters): that is `APPLE_KEY_ID`.

### 1d. "Configure Sign in with Apple for Email Communication" (yes, do it)

Where: *Certificates, Identifiers & Profiles* > the **Services** / **More** section in the left menu >
**Configure Sign in with Apple for Email Communication** (the page that says "register email sources").

Why: a person who signs in with Apple can choose **Hide My Email**. Apple then gives us an address like
`abc123@privaterelay.appleid.com` that forwards to them, **but only for senders you registered**; mail from anyone
else is dropped. Rysteria mails that address when it is the only one a person has (the confirmation of an
email, the code for a password reset or an account deletion go to an address the provider vouches for).
Without the registration those codes would silently never arrive for Hide-My-Email users.

What to enter (Apple wants a domain or an address that passes SPF or DKIM):

| Field | Put |
|---|---|
| Domains | the domain the Resend automation sends from |
| Email Addresses | the exact sender address of that automation |

Entering the domain is enough; adding the address too does no harm. Apple then checks the domain's DNS: Resend's
verified domain (the DKIM and SPF records Resend shows when you add the domain, see [`KEYS.md`](KEYS.md)) satisfies it.
The address and domain must be the ones the Resend automation sends from. Wait until Resend says *Verified*, then press
**Save** on Apple's page. Test: sign in with Apple on the website choosing
*Hide My Email*, then ask for a password reset for that account and type the relay address: the mail must arrive.

Finally fill `secrets/master.env`:

```
APPLE_CLIENT_ID=blog.parshwa.rysteria.web
APPLE_TEAM_ID=DTAYB9YB9Y
APPLE_KEY_ID=<the key id from 1c>
APPLE_PRIVATE_KEY_FILE=~/.rysteria-secrets/apple.p8
```

then push the secrets and restart. When all of `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID` and
`APPLE_PRIVATE_KEY_FILE` are set, the Apple button appears on `/login`. **Test:** log in with Apple on the website
in a private window; a brand new Apple user is asked for a username and password (the "Finish your account" step).

## 2. An icon (the App Store refuses an app without one)

A **1024 x 1024 PNG, no transparency, square corners** (Apple rounds it). Save it as `phones/icon-1024.png` and run
`scripts-phones/make-icons.sh`. (Your `image.png` flower face has transparent corners: put it on a coloured
square first, e.g. the site's green `#1ea761`, in any image editor.)

## 3. The Mac

```sh
brew install xcodegen
```

Xcode is installed (27.0). Open Xcode once > *Settings > Accounts > +* > sign in with the developer Apple Account:
Xcode then makes the signing certificates and provisioning profiles by itself (`-allowProvisioningUpdates` in the
scripts). Then `scripts-phones/doctor.sh` must say Xcode and xcodegen are fine.

## 4. Try it on your own devices first

```sh
scripts-phones/ios-build.sh            # simulator
scripts-phones/ios-run.sh              # opens the Simulator with the game
```

Real iPhone: iPhone *Settings > Privacy & Security > Developer Mode* on (it restarts), plug it into the Mac, tap
*Trust*, `xcrun devicectl list devices` (copy the identifier), then
`scripts-phones/ios-run.sh --device <identifier>`.

**What to check:** the game loads in landscape; you land on `/login`; log in; sign up (the code arrives by email);
Google / Discord / Apple open in Apple's sheet and come back to the game; kill and reopen the app: still logged
in; `/account` opens from the Account screen; a link in the game to another site opens in Safari.

## 5. App Store Connect (appstoreconnect.apple.com)

### 5a. The app record: *Apps > + > New App*

| Field | Put |
|---|---|
| Platforms | iOS |
| Name | `Rysteria` (30 characters at most; must be free in the whole store, else add a word) |
| Primary language | English (U.S.) |
| Bundle ID | `Rysteria - blog.parshwa.rysteria` (it appears here after step 1a) |
| SKU | anything only you see, e.g. `rysteria-ios` |
| User Access | Full Access |

### 5b. App Store Connect API key (for `ios-deploy.sh --testflight` / `--production`)

*Users and Access > Integrations > App Store Connect API > Team Keys > +* Name `Rysteria deploy`, access
**App Manager**. Download the `AuthKey_XXXXXXXX.p8` (also once only), keep it outside the repository, and copy the
**Key ID** and the **Issuer ID** (top of the page) into `scripts-phones/phones.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_PATH`). Without them you can still upload by hand with Apple's **Transporter** app from the Mac App Store.

### 5c. Upload a build

```sh
scripts-phones/ios-deploy.sh --testflight     # archives, signs, asks "Send ...?" and uploads for TestFlight
```

Raise `VERSION_CODE` in `phones.env` every time (Apple refuses a build number it has seen). After 5 to 60 minutes
the build shows under *TestFlight > iOS Builds*.

### 5d. TestFlight (test on phones before the store)

*TestFlight > Internal Testing > +* make a group, add yourself (and up to 100 people who are users of your App
Store Connect team). Install **TestFlight** from the App Store on the iPhone, accept the invite, install Rysteria.
There is no review for internal testers. (External testers, anyone with a link, need a short Beta App Review.)

### 5e. From here on: the store page and the review

Everything for the App Store page (screenshots, texts, age rating, privacy answers, the demo account and review notes) and
the submission itself is in **[`APPLE_PRODUCTION.md`](APPLE_PRODUCTION.md)**. TestFlight needs none of it.

## 6. After it is live

* New game versions need **no** new app: the app loads the site.
* A new app version is only for changes in `phones/ios`: bump `VERSION_NAME` / `VERSION_CODE`,
  `scripts-phones/ios-deploy.sh --production`, select the build in a new version page, submit.
* Apple's notices (someone deleted their Apple Account) arrive at `ADMIN_EMAIL`.
