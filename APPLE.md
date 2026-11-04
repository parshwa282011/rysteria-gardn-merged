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

Next to the domain there is a **Download** link for a verification file. Do this *now*, in one go (Apple's file
only lives a few days):

1. Download the file (`apple-developer-domain-association.txt`).
2. Save it as `secrets/apple-domain.txt` in this repository.
3. In `secrets/master.env` set `APPLE_DOMAIN_FILE=~/.rysteria-secrets/apple-domain.txt`.
4. `scripts/push-secrets.sh user@host` to every machine, restart the master. It now serves the file at
   `https://api-game.parshwa.blog/.well-known/apple-developer-domain-association.txt` (open that address in a
   browser: you must see the file's text).
5. Back in Apple's dialog press **Verify**. Then *Next > Done > Continue > Save*.

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

Finally fill `secrets/master.env`:

```
APPLE_CLIENT_ID=blog.parshwa.rysteria.web
APPLE_TEAM_ID=DTAYB9YB9Y
APPLE_KEY_ID=<the key id from 1c>
APPLE_PRIVATE_KEY_FILE=~/.rysteria-secrets/apple.p8
APPLE_DOMAIN_FILE=~/.rysteria-secrets/apple-domain.txt
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

### 5b. App Store Connect API key (for `ios-deploy.sh --upload`)

*Users and Access > Integrations > App Store Connect API > Team Keys > +* Name `Rysteria deploy`, access
**App Manager**. Download the `AuthKey_XXXXXXXX.p8` (also once only), keep it outside the repository, and copy the
**Key ID** and the **Issuer ID** (top of the page) into `scripts-phones/phones.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_PATH`). Without them you can still upload by hand with Apple's **Transporter** app from the Mac App Store.

### 5c. Upload a build

```sh
scripts-phones/ios-deploy.sh --upload     # archives, signs, asks "Send ...?" and uploads
```

Raise `VERSION_CODE` in `phones.env` every time (Apple refuses a build number it has seen). After 5 to 60 minutes
the build shows under *TestFlight > iOS Builds*.

### 5d. TestFlight (test on phones before the store)

*TestFlight > Internal Testing > +* make a group, add yourself (and up to 100 people who are users of your App
Store Connect team). Install **TestFlight** from the App Store on the iPhone, accept the invite, install Rysteria.
There is no review for internal testers. (External testers, anyone with a link, need a short Beta App Review.)

### 5e. The store page: *App Store > the version "1.0 Prepare for Submission"*

| Field | Put |
|---|---|
| Screenshots | iPhone **6.9"** is required (the 6.5" ones are optional; Apple scales them). Take them in the Simulator (an iPhone 16/17 Pro Max) with *Cmd+S*, landscape, 1320 x 2868 or 2868 x 1320. 3 to 10 of them. The app is iPhone-only, so no iPad screenshots |
| Promotional text | one sentence (optional) |
| Description | what the game is, that it is free with accounts, that chat and leaderboards are online |
| Keywords | `petals,flower,io,multiplayer,survival,mmo,arena` (100 characters total, comma separated, no spaces) |
| Support URL | `https://game.parshwa.blog/` (a page that shows how to reach you; the privacy policy page has your email: `https://game.parshwa.blog/privacy` is fine too) |
| Marketing URL | optional |
| Version | `1.0` |
| Copyright | `2026 Tejashkumar Shah` |
| Build | pick the one you uploaded (*+ Add Build*). It asks about export compliance only if the plist key is missing; `ITSAppUsesNonExemptEncryption` is already `false` in the project, answer *No* if it asks |

### 5f. *App Information* (left menu)

| Field | Put |
|---|---|
| Category | Primary **Games**, subcategory Action (or Adventure) |
| Content Rights | *Does your app contain, show, or access third-party content?* **No** |
| Age Rating | press *Edit* and answer the questionnaire honestly: **Unrestricted web access: No** (the app only opens the game; other links go to Safari); **User-generated content / chat: Yes**; violence in a game: cartoon, mild; no gambling, no real-money purchases, no mature content. Expect 12+ or 13+ |
| Privacy Policy URL | `https://game.parshwa.blog/privacy` |

### 5g. *App Privacy* (the "nutrition label")

*Get Started*, "Do you or your third-party partners collect data from this app?" **Yes**, then add:

| Data type | Linked to the user | Used for | Tracking |
|---|---|---|---|
| Contact Info > Email Address | Yes | App Functionality (codes, account) | No |
| Contact Info > Name (the display name a provider gives) | Yes | App Functionality | No |
| User Content > Other User Content (chat messages) | Yes | App Functionality | No |
| Identifiers > User ID (account id) | Yes | App Functionality | No |
| Usage Data > Gameplay Content (progress, scores) | Yes | App Functionality | No |

Everything *not used for tracking* (no ads, no analytics, no data sold: "Do you use data for tracking? No").

### 5h. *Pricing and Availability*: Free, all countries (or leave the EU out if you do not want to deal with the EU rules).

### 5i. *App Review Information* (this decides whether you pass)

| Field | Put |
|---|---|
| Contact | your name, phone, email |
| **Sign-in required** | tick it, and give a **demo account**: make it on the website, **confirm its email** (otherwise the reviewer is stopped at the confirmation step) and write its username and password here |
| Notes | see below |

Notes to paste:

> Rysteria is a free multiplayer game (the game itself runs on game.parshwa.blog; the app is its iOS front end).
> Log in with the demo account above, or tap "Sign up". Sign in with Apple, Google and Discord are on the login page.
> Account deletion: in the game open the Account screen, tap "Manage account" (or go to /account), "Delete my
> account": it asks for the password and a code that is emailed to the account. In-game chat is filtered and
> needs level 3; player reports go to the email in the privacy policy.

## 6. The things Apple reviewers actually bounce, and where you stand

| Guideline | What it asks | Status |
|---|---|---|
| **4.8 Login services** | Offer Sign in with Apple if you offer Google/Discord | Done (button appears once step 1 is configured) |
| **5.1.1(v) Account deletion** | Start deleting the account inside the app | Done: the Account screen opens `/account` with password + emailed code + typed username. Apple's token is revoked on deletion |
| **5.1.1 Privacy policy** | A link in the store page and in the app | Store page: `/privacy`. The login page links to it too |
| **4.2 Minimum functionality** | An app that is only a website is often refused | **The real risk.** It is a live multiplayer game with accounts, and the notes above say so, but be ready for a "your app is a web view" reply. If it happens, answer that the game needs live servers and that the app adds system sign-in, and ask for a call. Adding something native (a "no connection" screen, haptics, a splash) helps |
| **1.2 User-generated content** | Filter, a way to report and block, published contact | Chat is filtered. I did **not** find a report or block button in the game: Apple may ask. Say reports go by email, or ask me to add a report button |
| **2.1 App completeness** | It must not crash, links must work | Test it on a real iPhone with TestFlight first |
| **2.3 / 5.2** | Screenshots show the real game, no other apps' names | Use real screenshots |

When everything is filled in: *Add for Review > Submit to App Review*. First reviews take a day or two. Choose
*Manually release this version* if you want to press the button yourself.

## 7. After it is live

* New game versions need **no** new app: the app loads the site.
* A new app version is only for changes in `phones/ios`: bump `VERSION_NAME` / `VERSION_CODE`, `ios-deploy.sh --upload`,
  select the build in a new version page, submit.
* Apple's notices (someone deleted their Apple Account) arrive at `ADMIN_EMAIL`.
