#!/usr/bin/env bash
# Builds the Android app on this laptop.
#   scripts-phones/android-build.sh            debug APK (signed with the debug key, installs anywhere)
#   scripts-phones/android-build.sh --lint     also runs the Android lint checks
#   --dry-run  only prints what it would do
# Result: builds/phones/rysteria-debug.apk
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
lint=0
for a in "${PH_ARGS[@]+"${PH_ARGS[@]}"}"; do
    case "$a" in --lint) lint=1 ;; *) die "unknown option $a" ;; esac
done
load_settings
pick_java
pick_android_sdk

log "debug build of the app for $GAME_URL"
tasks=(assembleDebug)
[ "$lint" = 1 ] && tasks+=(lintDebug)
gradle_run "${tasks[@]}"

run mkdir -p "$PH_OUT"
run cp "$PH_ANDROID/app/build/outputs/apk/debug/app-debug.apk" "$PH_OUT/rysteria-debug.apk"
log "done: $PH_OUT/rysteria-debug.apk"
