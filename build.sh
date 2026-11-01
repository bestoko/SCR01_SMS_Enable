#!/system/bin/sh
# Rebuild the payload from src/ (requires Android SDK build-tools on the host).
# Prerequisites:
#   - aapt2  (Android SDK build-tools)
#   - d8     (Android SDK build-tools)
#   - javac  (JDK 8+)
#   - android.jar (Android SDK platforms/android-30)
#
# Outputs into module/payload/ :
#   - scr01-dynamic-sms.apk   (minimal theme overlay: config_sms_capable=true)
#   - SmsRoleProbe.dex        (role-name helper)
set -e

SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
BT="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"
PLATFORM="$SDK/platforms/android-30/android.jar"
ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP="$ROOT/.build"
rm -rf "$TMP"; mkdir -p "$TMP"

# --- 1. RRO overlay APK ---
mkdir -p "$TMP/rro"
"$BT/aapt2" compile --dir "$ROOT/src/overlay/res" -o "$TMP/rro/res.zip"
"$BT/aapt2" link -o "$ROOT/module/payload/scr01-dynamic-sms.apk" \
    -I "$PLATFORM" --manifest "$ROOT/src/overlay/AndroidManifest.xml" \
    "$TMP/rro/res.zip"

# --- 2. SmsRoleProbe.dex ---
mkdir -p "$TMP/dex"
javac -source 8 -target 8 -cp "$PLATFORM" \
    -d "$TMP/dex" "$ROOT/src/SmsRoleProbe.java"
"$BT/d8" --output "$TMP/dex" "$TMP/dex/SmsRoleProbe.class"
mv "$TMP/dex/classes.dex" "$ROOT/module/payload/SmsRoleProbe.dex"

rm -rf "$TMP"
echo "payload rebuilt into module/payload/"
