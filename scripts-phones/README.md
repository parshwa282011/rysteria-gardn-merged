# Phone scripts

Build, try and publish the Android and iOS apps from `phones/`. **Everything here runs on your laptop, only when you
start it.** Nothing in `scripts/` (build, run, deploy, the servers, cron) calls these, and they never touch the
servers or their machines (c1, the Pi).

| Script | What it does |
|---|---|
| `doctor.sh` | Checks the laptop for everything below and says what to install. Changes nothing. |
| `make-icons.sh` | Makes both apps' icons from one 1024x1024 PNG. |
| `make-keystore.sh` | Makes the Android signing key once (`phones.env` says where). |
| `android-build.sh` | Debug APK → `builds/phones/rysteria-debug.apk`. `--lint` also runs the Android checks. |
| `android-run.sh` | Installs it on a phone / emulator and starts it. `--avd NAME` starts an emulator, `--logcat` shows the log. |
| `android-deploy.sh` | **Signed** release bundle (`.aab`, for Google Play) and APK. Uploads nothing. |
| `ios-build.sh` | Builds for the simulator (no Apple account needed) or `device`. |
| `ios-run.sh` | Starts it in the simulator, or `--device <id>` on a plugged-in iPhone. |
| `ios-deploy.sh` | Archives and makes the App Store `.ipa`. **`--testflight`** sends it to App Store Connect for TestFlight testing, **`--production`** sends the build you will submit to review (after checks, and a typed "production"). |

**TestFlight or production?** There is one upload; the choice is made in the store's console. Every uploaded iOS build shows
up in TestFlight; "production" means you pick a build on the app's version page and press *Add for Review*
([`APPLE_PRODUCTION.md`](../APPLE_PRODUCTION.md)). `--testflight` just uploads and tells you how to install it;
`--production` runs the checks first (site pages up, icon, API key, new build number), asks you to type
`production`, uploads, and prints what is left to do. On Google Play the same split is the *track*: you upload the
`.aab` to **Internal testing** first and later promote that release to **Production** (see below).

Every script takes `--dry-run` (prints what it would do, does nothing). Settings live in `phones.env`
(git-ignored; copy of `phones.env.example`). Lines that still need you say `#TODO: ADD THE INFO`.

The apps open `https://game.parshwa.blog/` in a web view, so a game update never needs a new app version. You only
publish a new version when the *app* changes (icons, the rules of the stores, the web view code).

## First time on this laptop (about 30 minutes, once)

```sh
brew install openjdk@21 gradle xcodegen      # xcodegen only for iOS
```

* **Android Studio** (https://developer.android.com/studio): install it and open it once. It installs the Android SDK
  (`~/Library/Android/sdk`). In *Settings > Languages & Frameworks > Android SDK > SDK Tools* tick **Android SDK
  Platform-Tools**, **Android Emulator**, and in *SDK Platforms* **Android 16 (API 36)**. Then accept the licenses:
  `~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --licenses`.
* **Xcode** from the App Store (iOS only). Open it once, accept the license, then
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Install an iOS Simulator runtime when it offers.
* `cp phones.env.example phones.env` and fill what you know.
* `scripts-phones/doctor.sh` until it says everything is there.

The apps' Gradle wrapper (Gradle 8.11.1, the Homebrew one is too new for the Android plugin) is made by the first
Android script and is git-ignored.

### Icons (both stores refuse an app without one)

Make a square **1024x1024 PNG, no transparency, no rounded corners** and save it as `phones/icon-1024.png`
(the game's `logo.png` is only 60 px, too small). Then `scripts-phones/make-icons.sh`. It writes the Android
`mipmap-*` icons, the iOS `AppIcon` set and sets `android:icon`; commit the results.

## Android

### Try it

```sh
scripts-phones/android-build.sh            # builds/phones/rysteria-debug.apk
scripts-phones/android-run.sh              # on a phone with USB debugging, or a running emulator
```

* **A real phone**: Settings > About phone > tap *Build number* 7 times > Developer options > **USB debugging**; plug it
  in, accept the prompt on the phone. `adb devices` (in `~/Library/Android/sdk/platform-tools`) must list it.
* **An emulator** (once): Android Studio > *Device Manager* > Create device (e.g. Pixel 8, API 36 image), or
  `sdkmanager "system-images;android-36;google_apis;arm64-v8a"` and
  `avdmanager create avd -n Pixel_8 -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8`.
  Then `scripts-phones/android-run.sh --avd Pixel_8`.

What to check: the game loads; you are sent to `/login` and back; log in; sign up (the code arrives by email);
**Google / Discord / Apple** open in the browser sheet and come back to the app (that is the `rysteria://oauth`
link); close and reopen the app and you are still logged in; rotate the phone.

### Make the Android keystore (once, for publishing)

The key that signs your app. **Keep the file outside the repository and back it up** (a password manager, a USB
stick): lose it and you can not update the app without Google's key reset.

```sh
scripts-phones/make-keystore.sh
```

It asks for a password (twice), makes `~/.rysteria-phones/rysteria-upload.jks` (the path and alias in `phones.env`)
and shows the key's fingerprint. The password is asked for each time `android-deploy.sh` runs; it is never written
anywhere.

### Publish on Google Play

1. **Developer account**: https://play.google.com/console/signup, 25 USD once, identity check (takes days sometimes).
2. **Create app** in the Play Console: name, language, *App*, *Free*. Accept **Play App Signing** (the default): Google
   holds the real signing key, the keystore above is only your *upload* key.
3. **Fill the "App content" pages** (the console lists them): privacy policy URL (you need a page on a site you own),
   Data safety (account email/username, in-game progress; data is encrypted in transit), content rating
   questionnaire, target audience, ads = no. Add the store listing: short + full description, icon 512x512,
   feature graphic 1024x500, at least 2 phone screenshots.
4. `scripts-phones/android-deploy.sh` → `builds/phones/rysteria-<version>-<code>.aab`. Raise `VERSION_CODE` in
   `phones.env` before every upload (the console refuses a code it has seen).
5. **Internal testing** (the test track): *Testing > Internal testing > Create new release*, upload the `.aab`,
   *Save > Next > Start rollout*. Add testers under the *Testers* tab (a list of Google accounts, up to 100), copy the
   opt-in link, open it on the phone, install. No review, available within minutes. Check the list above again.
6. **Production** (the real release): *Production > Create new release*; either upload the same `.aab` again or
   **Add from library** to reuse the one you tested (same version code, which proves it is the build you tried).
   A *personal* developer account created after November 2023 must first run a **closed test with
   at least 12 testers opted in for 14 days in a row**, then fill the production-access form. An *organization*
   account does not have this rule. Then *Production > Create release*, upload the same `.aab`.

Google's rule since 31 August 2026: new apps and updates must **target Android 16 (API level 36)**. The project
already does (`compileSdk`/`targetSdk` 36 in `phones/android/app/build.gradle.kts`); the Play Console tells you
if a newer level is asked for. Note the build was never run in this repository's environment: if the first
`android-build.sh` fails, it is probably a version number (the Android Gradle plugin in
`phones/android/build.gradle.kts`, or Kotlin) — the error names it.

## iOS

### Try it

```sh
scripts-phones/ios-build.sh        # simulator, no account needed
scripts-phones/ios-run.sh          # opens the Simulator, installs, starts
```

**A real iPhone** needs your Apple team: put `IOS_TEAM_ID` in `phones.env`, switch on *Developer Mode* on the
iPhone (Settings > Privacy & Security), plug it in and trust the Mac, then
`xcrun devicectl list devices` for its id and `scripts-phones/ios-run.sh --device <id>`. A free Apple ID works for
a 7-day install; the paid program is needed for TestFlight and the store.

### Apple accounts, ids, keys (the whole Apple setup is in [`APPLE.md`](../APPLE.md), the review in [`APPLE_PRODUCTION.md`](../APPLE_PRODUCTION.md))

1. **Apple Developer Program**: https://developer.apple.com/programs/enroll/ , 99 USD a year (company enrolment
   needs a D-U-N-S number, individual does not).
2. **Team ID** (`IOS_TEAM_ID`): https://developer.apple.com/account > *Membership details* > **Team ID**
   (10 letters/digits).
3. **Bundle ID** (the same as `APP_ID`, `blog.parshwa.rysteria`): *Certificates, Identifiers & Profiles > Identifiers >
   + > App IDs > App*, description Rysteria, explicit bundle id. Tick the capability **Sign in with Apple** (this is
   also the "primary App ID" that the web sign in below belongs to).
4. **App record**: https://appstoreconnect.apple.com > *Apps > + > New App*: iOS, name, language, pick that bundle
   id, any SKU.
5. **App Store Connect API key** (for `ios-deploy.sh --testflight/--production`): appstoreconnect.apple.com > *Users and Access >
   Integrations > App Store Connect API > Team Keys > +*, access **App Manager**. Download the `AuthKey_XXXX.p8`
   (**only once**, keep it outside the repo), and copy the **Key ID** (`ASC_KEY_ID`) and the **Issuer ID** at the top of
   the page (`ASC_ISSUER_ID`). `ASC_KEY_PATH` is the file's path.

### Publish on the App Store

1. `scripts-phones/ios-deploy.sh` makes the archive and `builds/phones/ios-release/Rysteria.ipa` and uploads nothing.
   `--testflight` sends it to App Store Connect for testing, `--production` sends the build you will submit to review.
   Raise `VERSION_CODE` for each upload.
2. After a few minutes to an hour the build shows under *TestFlight*. Add yourself under *Internal Testing*, install
   the **TestFlight** app on the iPhone, and test the list above.
3. For the store: screenshots (6.9" iPhone size is enough to start), description, **privacy policy URL**, age rating,
   *App Privacy* answers (email, username, gameplay data linked to the user), then *Submit for review*.
4. **Give the reviewers a login.** The app needs an account: create one on the site, confirm its email, and put the
   username and password in *App Review Information > Sign-in required*. Say that the game itself runs on the
   website (guideline 4.2 asks for more than "a website in a box"; live servers and accounts normally pass).
   Guideline 4.8 wants Sign in with Apple next to Google: it is there once Apple sign in is configured.

## The sign-in keys the apps rely on

The apps use the same Google / Apple / Discord setup as the website, and the `rysteria://oauth` link needs nothing
else. The keys and how to get them are in [`KEYS.md`](../KEYS.md).
