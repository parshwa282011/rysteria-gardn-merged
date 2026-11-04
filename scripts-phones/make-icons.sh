#!/usr/bin/env bash
# Makes the app icons for both apps from ONE square PNG, 1024x1024, no transparency, no rounded corners
# (the stores round it themselves). The game's own logo (rrolf/Client/public/logo.png) is only 60 pixels:
# too small. Put your artwork at phones/icon-1024.png (or pass another path).
#   scripts-phones/make-icons.sh [path/to/icon-1024.png]
# Writes phones/android/app/src/main/res/mipmap-*/ic_launcher.png and
# phones/ios/Rysteria/Assets.xcassets/AppIcon.appiconset/ (both are small and can be committed).
source "$(dirname "$0")/lib.sh"
parse_flags "$@"
src="${PH_ARGS[0]:-$PH_ROOT/phones/icon-1024.png}"
[ -f "$src" ] || die "no icon at $src. Put a 1024x1024 PNG there (see README.md, \"Icons\")"
need_tool sips "This script uses macOS's sips"
w="$(sips -g pixelWidth "$src" | awk '/pixelWidth/ {print $2}')"
h="$(sips -g pixelHeight "$src" | awk '/pixelHeight/ {print $2}')"
[ "$w" = 1024 ] && [ "$h" = 1024 ] || die "$src is ${w}x${h}, it has to be 1024x1024"

res="$PH_ANDROID/app/src/main/res"
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    dir="$res/mipmap-${pair%%:*}"
    run mkdir -p "$dir"
    run sips -z "${pair##*:}" "${pair##*:}" "$src" --out "$dir/ic_launcher.png" >/dev/null
done
manifest="$PH_ANDROID/app/src/main/AndroidManifest.xml"
if ! grep -q 'android:icon=' "$manifest"; then
    run sed -i '' 's|<application|<application\n        android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher"|' "$manifest"
    log "set android:icon in AndroidManifest.xml"
fi

set_dir="$PH_IOS/Rysteria/Assets.xcassets/AppIcon.appiconset"
run mkdir -p "$set_dir"
run cp "$src" "$set_dir/icon-1024.png"
if [ "$PH_DRY_RUN" != 1 ]; then
    cat >"$PH_IOS/Rysteria/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
    cat >"$set_dir/Contents.json" <<'JSON'
{
  "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
fi
log "icons written for Android and iOS"
