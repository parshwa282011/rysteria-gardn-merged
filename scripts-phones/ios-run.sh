#!/usr/bin/env bash
# Starts the iOS app on the simulator (default) or on a plugged in iPhone.
#   scripts-phones/ios-run.sh                         simulator (first iPhone it finds, or --sim "iPhone 16")
#   scripts-phones/ios-run.sh --device <id>           a real iPhone (ids: xcrun devicectl list devices)
#   scripts-phones/ios-run.sh --rebuild               builds again even if the app is there
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
sim="" device="" rebuild=0
set -- "${PH_ARGS[@]+"${PH_ARGS[@]}"}"
while [ $# -gt 0 ]; do
    case "$1" in
    --sim) sim="${2:?--sim needs a name}"; shift ;;
    --device) device="${2:?--device needs an id}"; shift ;;
    --rebuild) rebuild=1 ;;
    *) die "unknown option $1" ;;
    esac
    shift
done
load_settings
need_tool xcrun "Install Xcode"

if [ -n "$device" ]; then
    app="$PH_OUT/ios-device/Rysteria.app"
    if [ "$rebuild" = 1 ] || [ ! -d "$app" ]; then "$PH_DIR/ios-build.sh" device $([ "$PH_DRY_RUN" = 1 ] && echo --dry-run); fi
    log "installing on the iPhone"
    run xcrun devicectl device install app --device "$device" "$app"
    log "starting it"
    run xcrun devicectl device process launch --device "$device" "$APP_ID"
    exit 0
fi

app="$PH_OUT/ios-simulator/Rysteria.app"
if [ "$rebuild" = 1 ] || [ ! -d "$app" ]; then "$PH_DIR/ios-build.sh" simulator $([ "$PH_DRY_RUN" = 1 ] && echo --dry-run); fi

if [ -z "$sim" ]; then
    sim="$(xcrun simctl list devices available | sed -n 's/^ *\(iPhone [^(]*[^ (]\) (.*/\1/p' | head -1)"
    [ -n "$sim" ] || die "no iPhone simulator found. Xcode > Settings > Components (or Platforms) > install an iOS runtime"
fi
log "simulator: $sim"
run xcrun simctl boot "$sim" || true
run open -a Simulator
run xcrun simctl install "$sim" "$app"
run xcrun simctl launch "$sim" "$APP_ID"
