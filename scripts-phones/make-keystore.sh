#!/usr/bin/env bash
# Makes the Android upload keystore once (the key that signs your app for Google Play). The path and the
# alias come from phones.env (ANDROID_KEYSTORE, ANDROID_KEY_ALIAS). Nothing is uploaded anywhere.
#   scripts-phones/make-keystore.sh
# It asks for a password (twice). You need that password for every release: keep it in a password manager,
# and BACK UP THE FILE ITSELF (a password manager attachment, a USB stick): losing either means a key reset
# request to Google. The file stays OUTSIDE the repository.
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
load_settings
need_setting ANDROID_KEYSTORE "where the keystore file goes"
need_setting ANDROID_KEY_ALIAS "the key's name inside the keystore"
pick_java
keytool="$JAVA_HOME/bin/keytool"
[ -x "$keytool" ] || die "keytool not found in $JAVA_HOME (install a JDK: brew install openjdk@21)"
[ ! -e "$ANDROID_KEYSTORE" ] || die "$ANDROID_KEYSTORE exists already: not touching it"

dir="$(dirname "$ANDROID_KEYSTORE")"
run mkdir -p "$dir"
run chmod 700 "$dir"
if [ "$PH_DRY_RUN" = 1 ]; then
    echo "[dry-run] keytool -genkeypair -keystore $ANDROID_KEYSTORE -alias $ANDROID_KEY_ALIAS -keyalg RSA -keysize 2048 -validity 10000"
    exit 0
fi
ask_secret KS_PASSWORD "Choose the keystore password (at least 6 characters)"
read -r -s -p "Again: " again
printf '\n'
[ "$KS_PASSWORD" = "$again" ] || die "the two passwords differ"
log "making the keystore"
# the key password is the same as the keystore's: one thing to remember
"$keytool" -genkeypair -keystore "$ANDROID_KEYSTORE" -alias "$ANDROID_KEY_ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Rysteria" \
    -storepass:env KS_PASSWORD -keypass:env KS_PASSWORD
chmod 600 "$ANDROID_KEYSTORE"
log "made $ANDROID_KEYSTORE"
"$keytool" -list -keystore "$ANDROID_KEYSTORE" -alias "$ANDROID_KEY_ALIAS" -storepass:env KS_PASSWORD | tail -2
unset KS_PASSWORD again
cat <<'DONE'

Now: 1. copy the .jks file somewhere safe (not only this laptop)  2. remember the password
     3. scripts-phones/android-deploy.sh asks for it (twice, the same one) when it builds a release
DONE
