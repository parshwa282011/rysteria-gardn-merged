#!/usr/bin/env bash
# Makes the App Store build of the iOS app (an archive, then the .ipa).
#   scripts-phones/ios-deploy.sh             builds builds/phones/ios-release/Rysteria.ipa, uploads nothing
#   scripts-phones/ios-deploy.sh --upload    also sends it to App Store Connect (TestFlight); asks first
# Needs IOS_TEAM_ID in phones.env, an app record in App Store Connect with the same bundle id, and for
# --upload an App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH). The build number
# (VERSION_CODE) has to go up with every upload.
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
upload=0
for a in "${PH_ARGS[@]+"${PH_ARGS[@]}"}"; do
    case "$a" in --upload) upload=1 ;; *) die "unknown option $a" ;; esac
done
load_settings
need_setting IOS_TEAM_ID "your Apple Developer Team ID"
auth=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
    [ "$PH_DRY_RUN" = 1 ] || [ -f "$ASC_KEY_PATH" ] || die "ASC_KEY_PATH $ASC_KEY_PATH does not exist"
    auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [ "$upload" = 1 ]; then
    need_setting ASC_KEY_ID "App Store Connect API key id"
    need_setting ASC_ISSUER_ID "App Store Connect issuer id"
    need_setting ASC_KEY_PATH "path of the AuthKey .p8 file"
fi
ios_generate
ios_settings

out="$PH_OUT/ios-release"
archive="$out/Rysteria.xcarchive"
run rm -rf "$out"
run mkdir -p "$out"

log "archive $VERSION_NAME ($VERSION_CODE) of the app for $GAME_URL"
run xcodebuild -project "$PH_IOS/Rysteria.xcodeproj" -scheme Rysteria -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    "DEVELOPMENT_TEAM=$IOS_TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
    "${auth[@]+"${auth[@]}"}" "${IOS_SETTINGS[@]}" archive

dest=export
if [ "$upload" = 1 ]; then
    confirm "Send $APP_ID $VERSION_NAME ($VERSION_CODE) to App Store Connect now?"
    dest=upload
fi
plist="$out/ExportOptions.plist"
[ "$PH_DRY_RUN" = 1 ] && plist=/dev/null
cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$IOS_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$dest</string>
</dict></plist>
PLIST

log "export ($dest)"
run xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out" -exportOptionsPlist "$plist" \
    -allowProvisioningUpdates "${auth[@]+"${auth[@]}"}"

if [ "$upload" = 1 ]; then
    log "sent. It shows up in App Store Connect > TestFlight after Apple has processed it (a few minutes to an hour)"
else
    log "done: $out/Rysteria.ipa  (add --upload to send it to App Store Connect, or use the Transporter app)"
fi
