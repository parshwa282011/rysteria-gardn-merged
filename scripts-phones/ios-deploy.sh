#!/usr/bin/env bash
# Makes the App Store build of the iOS app (an archive, then the .ipa) and, when you say so, sends it to
# App Store Connect. There is ONE upload; what happens next is decided in App Store Connect:
#   TestFlight  every uploaded build shows up there after Apple has processed it (5 to 60 minutes)
#   production  you pick a build on the app's version page and press "Add for Review" (APPLE_PRODUCTION.md)
#
#   scripts-phones/ios-deploy.sh                  build the .ipa only (builds/phones/ios-release/Rysteria.ipa), upload nothing
#   scripts-phones/ios-deploy.sh --testflight     build and upload for TestFlight testing (asks first)
#   scripts-phones/ios-deploy.sh --production     build and upload as the build you will send to review: checks that the
#                                                 site pages Apple opens answer, that the icon exists and that the build
#                                                 number is new, asks you to type "production", uploads, and prints the
#                                                 steps that are left in App Store Connect
#   --upload is the same as --testflight. --dry-run prints what would happen.
# Needs IOS_TEAM_ID in phones.env, an app record in App Store Connect with the same bundle id, and for the
# upload an App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH). The build number
# (VERSION_CODE) has to go up with every upload; the script refuses one it already sent.
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
upload=0 production=0
for a in "${PH_ARGS[@]+"${PH_ARGS[@]}"}"; do
    case "$a" in
    --upload | --testflight) upload=1 ;;
    --production) upload=1 production=1 ;;
    *) die "unknown option $a" ;;
    esac
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

# the build number is a one way street: Apple refuses a number it has seen
sent_file="$PH_OUT/ios-last-upload"
if [ "$upload" = 1 ] && [ -f "$sent_file" ]; then
    last="$(cat "$sent_file")"
    if [ "$last" = "$VERSION_NAME $VERSION_CODE" ]; then
        die "$VERSION_NAME ($VERSION_CODE) was already sent. Raise VERSION_CODE in phones.env"
    fi
fi

if [ "$production" = 1 ]; then
    log "checks before a production build"
    problems=0
    for page in "" privacy terms account login; do
        code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "${GAME_URL}${page}" || true)"
        if [ "$code" = 200 ]; then printf '  ok       %s%s\n' "$GAME_URL" "$page"
        else printf '  PROBLEM  %s%s answers %s (Apple opens it during review; the servers must be up)\n' "$GAME_URL" "$page" "$code"; problems=1; fi
    done
    if [ -f "$PH_ROOT/phones/ios/Rysteria/Assets.xcassets/AppIcon.appiconset/icon-1024.png" ]; then echo "  ok       app icon"
    else echo "  PROBLEM  no app icon: phones/icon-1024.png and scripts-phones/make-icons.sh (README.md)"; problems=1; fi
    [ -n "${ASC_KEY_ID:-}" ] && [ -f "${ASC_KEY_PATH:-/none}" ] && echo "  ok       App Store Connect API key" \
        || { echo "  PROBLEM  App Store Connect API key missing (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)"; problems=1; }
    echo "  note     read APPLE_PRODUCTION.md: the demo account, the review notes and the privacy answers are filled in App Store Connect"
    if [ "$PH_DRY_RUN" != 1 ]; then
        [ "$problems" = 0 ] || die "fix the problems above first"
        read -r -p 'Type "production" to build and upload the build you will send to review: ' answer
        [ "$answer" = production ] || die "stopped"
    fi
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
    [ "$production" = 1 ] || confirm "Send $APP_ID $VERSION_NAME ($VERSION_CODE) to App Store Connect (TestFlight) now?"
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
    [ "$PH_DRY_RUN" = 1 ] || printf '%s %s\n' "$VERSION_NAME" "$VERSION_CODE" >"$sent_file"
    log "sent. Apple now processes it (5 to 60 minutes; you get an email when it is ready)"
    if [ "$production" = 1 ]; then
        cat <<'NEXT'
What is left, in App Store Connect (https://appstoreconnect.apple.com > Apps > Rysteria):
  1. TestFlight: install this very build on your iPhone and play through the checklist in APPLE_PRODUCTION.md
  2. App Store > the version page > Build > "+": pick this build
  3. check every field against APPLE_PRODUCTION.md (screenshots, review notes, demo account)
  4. Add for Review > Submit to App Review
NEXT
    else
        echo "It appears under TestFlight > iOS Builds. Add yourself under Internal Testing and install it with the TestFlight app."
    fi
else
    log "done: $out/Rysteria.ipa  (--testflight or --production sends it to App Store Connect)"
fi
