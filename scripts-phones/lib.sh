#!/usr/bin/env bash
# Shared helpers for the phone scripts. Sourced, never executed. bash 3.2 (macOS) is enough.
#
# These scripts are for YOUR laptop and only run when you start them by hand. Nothing in
# scripts/ (build, run, deploy, the servers) calls them, and they never touch a server.

set -euo pipefail

PH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PH_ROOT="$(cd "$PH_DIR/.." && pwd)"
PH_ANDROID="$PH_ROOT/phones/android"
PH_IOS="$PH_ROOT/phones/ios"
PH_OUT="$PH_ROOT/builds/phones"          # git-ignored, safe to delete
PH_DRY_RUN="${PH_DRY_RUN:-0}"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$PH_DRY_RUN" = 1 ]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# --dry-run is understood by every script; the other arguments stay in PH_ARGS
PH_ARGS=()
parse_flags() {
    PH_ARGS=()
    local a
    for a in "$@"; do
        case "$a" in
        --dry-run) PH_DRY_RUN=1 ;;
        *) PH_ARGS+=("$a") ;;
        esac
    done
}

# ------------------------------------------------------------------- settings

# scripts-phones/phones.env (git-ignored). A value from the environment wins.
load_settings() {
    local file="$PH_DIR/phones.env" line key value
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in '' | '#'*) continue ;; esac
            key="${line%%=*}"
            value="${line#*=}"
            key="$(printf '%s' "$key" | tr -d '[:space:]')"
            [ -n "$key" ] || continue
            # the value may be quoted; ~ means the home folder
            case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
            esac
            case "$value" in '~/'*) value="$HOME/${value#\~/}" ;; esac
            if [ -z "${!key+x}" ]; then export "$key=$value"; fi
        done <"$file"
    else
        warn "no $file yet: using the defaults (copy phones.env.example to phones.env to change them)"
    fi
    GAME_URL="${GAME_URL:-https://game.parshwa.blog/}"
    API_HOST="${API_HOST:-api-game.parshwa.blog}"
    APP_ID="${APP_ID:-blog.parshwa.rysteria}"
    VERSION_NAME="${VERSION_NAME:-1.0}"
    VERSION_CODE="${VERSION_CODE:-1}"
}

# need_setting NAME "what it is": stops with a pointer when a value is still empty
need_setting() {
    local name="$1" what="$2"
    if [ -z "${!name:-}" ]; then
        die "$name ($what) is empty. Fill it in scripts-phones/phones.env (look for #TODO: ADD THE INFO), see scripts-phones/README.md"
    fi
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

# asks for a secret unless it is in the environment already (never stored, never printed)
ask_secret() {
    local name="$1" prompt="$2" value
    if [ -z "${!name:-}" ]; then
        [ -t 0 ] || die "$name is not set and there is no terminal to ask on"
        read -r -s -p "$prompt: " value
        printf '\n'
        export "$name=$value"
    fi
}

confirm() {
    [ "$PH_DRY_RUN" = 1 ] && return 0
    local answer
    read -r -p "$1 [y/N] " answer
    case "$answer" in y | Y | yes) return 0 ;; *) die "stopped" ;; esac
}

# ------------------------------------------------------------------- Android

# the JDK Gradle should run with: 17 to 21 (AGP 8.9 / Gradle 8.11); the newest Homebrew JDK is too new
pick_java() {
    local home="" v d
    if [ -x /usr/libexec/java_home ]; then
        for v in 21 17; do
            home="$(/usr/libexec/java_home -v "$v" 2>/dev/null || true)"
            [ -n "$home" ] && break
        done
    fi
    if [ -z "$home" ]; then
        for d in /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@21 /usr/local/opt/openjdk@17; do
            if [ -d "$d/libexec/openjdk.jdk/Contents/Home" ]; then home="$d/libexec/openjdk.jdk/Contents/Home"; break; fi
            if [ -x "$d/bin/java" ]; then home="$d"; break; fi
        done
    fi
    [ -n "$home" ] && export JAVA_HOME="$home"
    [ -n "${JAVA_HOME:-}" ] || die "no JDK 17 or 21 found. brew install openjdk@21 (see scripts-phones/README.md)"
}

pick_android_sdk() {
    local d
    if [ -z "${ANDROID_HOME:-}" ]; then
        for d in "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
            [ -n "$d" ] && [ -d "$d" ] && ANDROID_HOME="$d" && break
        done
    fi
    [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] || die "Android SDK not found. Install Android Studio once (it installs the SDK) or set ANDROID_HOME, see scripts-phones/README.md"
    export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
}

# the project has no Gradle wrapper checked in. The one Homebrew installs is newer than the Android
# plugin (8.9) accepts, so a wrapper for Gradle 8.11.1 is made once (in an empty folder, so the project
# is not read by the wrong Gradle) and copied in. It is git-ignored.
ensure_gradle_wrapper() {
    [ -x "$PH_ANDROID/gradlew" ] && return 0
    need_tool gradle "brew install gradle (only needed this once, to make the wrapper)"
    log "making the Gradle 8.11.1 wrapper"
    if [ "$PH_DRY_RUN" = 1 ]; then
        printf '[dry-run] gradle wrapper --gradle-version 8.11.1 (in an empty folder), copy to %s\n' "$PH_ANDROID"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    (cd "$tmp" && gradle wrapper --gradle-version 8.11.1 --no-daemon >/dev/null)
    cp -R "$tmp/gradle" "$PH_ANDROID/gradle"
    cp "$tmp/gradlew" "$tmp/gradlew.bat" "$PH_ANDROID/"
    rm -rf "$tmp"
}

# gradle_run TASK...: the -P switches carry the settings into build.gradle.kts
gradle_run() {
    ensure_gradle_wrapper
    run "$PH_ANDROID/gradlew" -p "$PH_ANDROID" \
        "-PgameUrl=$GAME_URL" "-PapiHost=$API_HOST" "-PappId=$APP_ID" \
        "-PversionName=$VERSION_NAME" "-PversionCode=$VERSION_CODE" "$@"
}

# ----------------------------------------------------------------------- iOS

ensure_xcodegen() {
    need_tool xcodebuild "Install Xcode from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app"
    need_tool xcodegen "brew install xcodegen"
}

# the Xcode project is made from phones/ios/project.yml every time (it is git-ignored)
ios_generate() {
    ensure_xcodegen
    log "xcodegen"
    (cd "$PH_IOS" && run xcodegen generate --quiet)
}

# settings for xcodebuild: what the app is pointed at, and its identity
ios_settings() {
    IOS_SETTINGS=("GAME_URL=$GAME_URL" "API_HOST=$API_HOST" "PRODUCT_BUNDLE_IDENTIFIER=$APP_ID"
        "MARKETING_VERSION=$VERSION_NAME" "CURRENT_PROJECT_VERSION=$VERSION_CODE")
}
