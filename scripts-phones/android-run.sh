#!/usr/bin/env bash
# Installs the debug app on a phone or emulator and starts it. Builds it first unless it is built.
#   scripts-phones/android-run.sh                 a phone with USB debugging, or a running emulator
#   scripts-phones/android-run.sh --avd Pixel_8   starts that emulator first (names: emulator -list-avds)
#   scripts-phones/android-run.sh --logcat        then shows the app's log (Ctrl-C to stop)
#   scripts-phones/android-run.sh --rebuild       builds again even if the APK is there
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
avd="" logcat=0 rebuild=0
set -- "${PH_ARGS[@]+"${PH_ARGS[@]}"}"
while [ $# -gt 0 ]; do
    case "$1" in
    --avd) avd="${2:?--avd needs a name}"; shift ;;
    --logcat) logcat=1 ;;
    --rebuild) rebuild=1 ;;
    *) die "unknown option $1" ;;
    esac
    shift
done
load_settings
pick_java
pick_android_sdk
need_tool adb "Android Studio installs it under platform-tools"

apk="$PH_OUT/rysteria-debug.apk"
if [ "$rebuild" = 1 ] || [ ! -f "$apk" ]; then
    "$PH_DIR/android-build.sh" $([ "$PH_DRY_RUN" = 1 ] && echo --dry-run)
fi

if [ -n "$avd" ]; then
    need_tool emulator "Android Studio > SDK Manager > SDK Tools > Android Emulator"
    log "starting the emulator $avd (a window opens)"
    if [ "$PH_DRY_RUN" = 1 ]; then
        echo "[dry-run] emulator -avd $avd &"
    else
        nohup emulator -avd "$avd" >"$PH_OUT/emulator.log" 2>&1 &
        adb wait-for-device
        log "waiting for it to finish booting"
        until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
    fi
fi

if [ "$PH_DRY_RUN" != 1 ]; then
    count="$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')"
    [ "$count" -ge 1 ] || die "no phone or emulator found. Plug a phone in with USB debugging on, or use --avd NAME (adb devices shows what is connected)"
fi
log "installing on the device"
run adb install -r "$apk"
log "starting it"
run adb shell am start -n "$APP_ID/blog.parshwa.rysteria.MainActivity"
if [ "$logcat" = 1 ]; then
    log "the app's log (Ctrl-C to stop)"
    run adb logcat --pid="$(adb shell pidof -s "$APP_ID" | tr -d '\r')"
fi
