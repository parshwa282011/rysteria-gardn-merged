#!/usr/bin/env bash
# Checks this laptop for everything the phone scripts need and says how to get what is missing.
# Changes nothing. Usage: scripts-phones/doctor.sh
source "$(dirname "$0")/lib.sh"
load_settings

bad=0
ok() { printf '  ok       %s\n' "$*"; }
miss() { printf '  MISSING  %s\n' "$*"; bad=1; }

echo "Android"
if v="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home -v 17 2>/dev/null || true)" && [ -n "$v" ]; then ok "JDK at $v"
elif [ -d /opt/homebrew/opt/openjdk@21 ] || [ -d /opt/homebrew/opt/openjdk@17 ]; then ok "JDK 17/21 from Homebrew"
else miss "JDK 17 or 21        -> brew install openjdk@21"; fi
if command -v gradle >/dev/null 2>&1 || [ -x "$PH_ANDROID/gradlew" ]; then ok "gradle (or the wrapper)"
else miss "gradle             -> brew install gradle (once, to make the wrapper)"; fi
sdk=""
for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do [ -n "$d" ] && [ -d "$d" ] && sdk="$d" && break; done
if [ -n "$sdk" ]; then
    ok "Android SDK at $sdk"
    [ -d "$sdk/platform-tools" ] && ok "platform-tools (adb)" || miss "platform-tools      -> Android Studio > Settings > Android SDK > SDK Tools"
    ls "$sdk/platforms" 2>/dev/null | grep -q "android-34" && ok "platform android-34" || warn_msg="(Gradle downloads it on the first build when the licenses are accepted: sdkmanager --licenses)"
    [ -n "${warn_msg:-}" ] && printf '  note     platform android-34 not installed yet %s\n' "$warn_msg"
    [ -d "$sdk/emulator" ] && ok "emulator" || printf '  note     no emulator installed: use a phone with USB debugging, or Android Studio > Device Manager\n'
else
    miss "Android SDK         -> install Android Studio once (https://developer.android.com/studio), open it, let it install the SDK"
fi
if [ -n "${ANDROID_KEYSTORE:-}" ] && [ -f "$ANDROID_KEYSTORE" ]; then ok "release keystore $ANDROID_KEYSTORE"
else printf '  note     no release keystore yet (only needed for android-deploy.sh): see README.md, "Make the Android keystore"\n'; fi

echo "iOS"
if [ "$(uname -s)" != Darwin ]; then
    printf '  note     iOS needs a Mac\n'
else
    if xcodebuild -version >/dev/null 2>&1; then ok "Xcode $(xcodebuild -version | head -1 | cut -d' ' -f2)"
    else miss "Xcode              -> install from the App Store, open it once, accept the license, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; fi
    command -v xcodegen >/dev/null 2>&1 && ok "xcodegen" || miss "xcodegen           -> brew install xcodegen"
    [ -n "${IOS_TEAM_ID:-}" ] && ok "IOS_TEAM_ID is set" || printf '  note     IOS_TEAM_ID is empty (needed to run on a real iPhone and for ios-deploy.sh)\n'
    [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -f "${ASC_KEY_PATH:-/none}" ] && ok "App Store Connect API key" || printf '  note     no App Store Connect API key (only needed for ios-deploy.sh --testflight/--production)\n'
fi

echo "Settings"
printf '  game %s   api %s   app id %s   version %s (%s)\n' "$GAME_URL" "$API_HOST" "$APP_ID" "$VERSION_NAME" "$VERSION_CODE"
[ -f "$PH_DIR/phones.env" ] && ok "scripts-phones/phones.env" || printf '  note     no phones.env yet (defaults are used)\n'
[ -f "$PH_ROOT/phones/icon-1024.png" ] && ok "phones/icon-1024.png (for make-icons.sh)" || printf '  note     no phones/icon-1024.png: the stores need an icon, see README.md\n'

[ "$bad" = 0 ] && echo "Everything you need for a first build is there." || { echo "Fix the MISSING lines first."; exit 1; }
