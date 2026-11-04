# Phone apps

Two small apps that open the game site in a web view, so they are always the version the servers
speak (nothing to update in the store when the game changes).

| | |
|---|---|
| `android/` | Kotlin, WebView + Custom Tabs. Targets Android 16 (API 36), which Google Play requires since 31 August 2026. |
| `ios/` | SwiftUI, WKWebView + ASWebAuthenticationSession. The Xcode project is made from `project.yml` by XcodeGen. |

**Build, run on a phone / emulator / simulator and publish with the scripts in [`../scripts-phones/`](../scripts-phones/README.md)**
(your laptop, by hand only). Neither app has been built in this repository's environment: expect to fix a version
number or two on the first build.

## Where they point

`GAME_URL` and `API_HOST`: `android/app/build.gradle.kts` (`buildConfigField`) and `ios/project.yml`
(`GAME_URL`, `API_HOST`). The defaults are `https://game.parshwa.blog/` and `api-game.parshwa.blog`.

## Signing in (OAuth)

Google refuses to sign in inside a web view, and Apple and Discord work better outside it. So:

1. The page sends the browser to `https://api-game.../oauth/<provider>/start`. The app catches that, adds `?app=1`,
   and opens it in a **Custom Tab** (Android) / **ASWebAuthenticationSession** (iOS).
2. The master remembers `app` with the sign in. When the provider is done it sends the browser to
   `rysteria://oauth#oauth_code=...` instead of the website (`MasterServer/c/oauth.c`).
3. The app owns the `rysteria` scheme (Android: the intent filter in `AndroidManifest.xml`; iOS: `CFBundleURLTypes`),
   catches it, and loads `https://game.parshwa.blog/#oauth_code=...` in its web view. The game forwards that to
   the log in page (`/login#oauth_code=...`), which exchanges the code like on the website, so the login is
   saved in the web view's own storage and the page returns to the game.

Password login, signup, confirming the email and the codes by email or Discord are the web page `/login`, which
works in the web view as it is.
Linking another provider to an account (Account screen) opens the provider in the browser too but is not wired
back to the app yet; do that on the website.

### What the providers need

* Google: an OAuth client of type *web*; its authorized redirect URI is the master's
  `https://api-game.../oauth/google/callback` (the same for the website and the apps, the master does the rest).
* Apple: a Services ID with the return URL `https://api-game.../oauth/apple/callback`, plus a key (`.p8`).
  Apple's guideline 4.8 asks for Sign in with Apple in an app that offers other social logins: it is there.
* `MasterServer/c/.env.example` lists the variables (`GOOGLE_*`, `APPLE_*`); [`../KEYS.md`](../KEYS.md) says where to get each.

## Store notes

* iOS: Apple also asks for a reason to exist beyond "a website in a box" (guideline 4.2); a game with its own
  accounts and live servers normally passes, but expect questions.
* Both stores need an icon: `scripts-phones/make-icons.sh` makes them from one 1024x1024 PNG.
