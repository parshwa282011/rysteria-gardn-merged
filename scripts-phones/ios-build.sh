#!/usr/bin/env bash
# Builds the iOS app on this Mac (it has to be a Mac with Xcode).
#   scripts-phones/ios-build.sh             for the simulator: needs no Apple account
#   scripts-phones/ios-build.sh device      for a real iPhone: needs IOS_TEAM_ID in phones.env
# Result: builds/phones/ios-simulator/Rysteria.app  or  builds/phones/ios-device/Rysteria.app
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
target=simulator
for a in "${PH_ARGS[@]+"${PH_ARGS[@]}"}"; do
    case "$a" in simulator | sim) target=simulator ;; device) target=device ;; *) die "unknown option $a (simulator or device)" ;; esac
done
load_settings
ios_generate
ios_settings

derived="$PH_OUT/ios-derived-$target"
if [ "$target" = simulator ]; then
    dest='generic/platform=iOS Simulator'
    sdkdir=Debug-iphonesimulator
    signing=(CODE_SIGNING_ALLOWED=NO)
else
    need_setting IOS_TEAM_ID "your Apple Developer Team ID"
    dest='generic/platform=iOS'
    sdkdir=Debug-iphoneos
    signing=("DEVELOPMENT_TEAM=$IOS_TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
fi

log "building for the $target (the app opens $GAME_URL)"
run xcodebuild -project "$PH_IOS/Rysteria.xcodeproj" -scheme Rysteria -configuration Debug \
    -destination "$dest" -derivedDataPath "$derived" "${IOS_SETTINGS[@]}" "${signing[@]}" build

run mkdir -p "$PH_OUT/ios-$target"
run rm -rf "$PH_OUT/ios-$target/Rysteria.app"
run cp -R "$derived/Build/Products/$sdkdir/Rysteria.app" "$PH_OUT/ios-$target/Rysteria.app"
log "done: $PH_OUT/ios-$target/Rysteria.app"
