#!/usr/bin/env bash
# Builds the SIGNED release of the Android app for the Play Store. Nothing is uploaded: Google Play
# Console takes the .aab file by hand (README.md, "Publish on Google Play").
#   scripts-phones/android-deploy.sh                  release bundle (.aab) and APK, signed with your keystore
#   scripts-phones/android-deploy.sh --install        also puts the release APK on the connected phone to try it
# The version code has to go up with every upload: change VERSION_CODE in phones.env first.
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
install=0
for a in "${PH_ARGS[@]+"${PH_ARGS[@]}"}"; do
    case "$a" in --install) install=1 ;; *) die "unknown option $a" ;; esac
done
load_settings
need_setting ANDROID_KEYSTORE "the keystore file you sign with"
need_setting ANDROID_KEY_ALIAS "the key's name inside the keystore"
[ "$PH_DRY_RUN" = 1 ] || [ -f "$ANDROID_KEYSTORE" ] || die "keystore $ANDROID_KEYSTORE does not exist. Make it first: README.md, \"Make the Android keystore\""
pick_java
pick_android_sdk
if [ "$PH_DRY_RUN" != 1 ]; then
    ask_secret ANDROID_KEYSTORE_PASSWORD "Keystore password"
    ask_secret ANDROID_KEY_PASSWORD "Key password (the same as above unless you chose another)"
fi
export ANDROID_KEYSTORE ANDROID_KEY_ALIAS

log "release build $VERSION_NAME (code $VERSION_CODE) of the app for $GAME_URL"
gradle_run bundleRelease assembleRelease

run mkdir -p "$PH_OUT"
aab="$PH_OUT/rysteria-$VERSION_NAME-$VERSION_CODE.aab"
apk="$PH_OUT/rysteria-$VERSION_NAME-$VERSION_CODE.apk"
run cp "$PH_ANDROID/app/build/outputs/bundle/release/app-release.aab" "$aab"
run cp "$PH_ANDROID/app/build/outputs/apk/release/app-release.apk" "$apk"
log "upload this to Google Play Console: $aab"
log "or try the release build on a phone:  $apk"

if [ "$install" = 1 ]; then
    need_tool adb "Android Studio installs it under platform-tools"
    run adb install -r "$apk"
fi
unset ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_PASSWORD
