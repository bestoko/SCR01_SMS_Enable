#!/system/bin/sh
# SCR-01 SMS Enable — diagnostic collector.
# Usage (root):
#   adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/collect-logs.sh'
#   adb pull /data/local/tmp/scr01_sms_diag_*.tar.gz
#
# The archive contains phone identifiers and SMS PDUs. Keep it local.

MODDIR=${0%/*}
TS=$(date +%Y%m%d-%H%M%S)
DIR=/data/local/tmp/scr01_sms_diag_$TS
mkdir -p "$DIR" 2>/dev/null

cp "$MODDIR"/boot-completed.log* "$DIR/" 2>/dev/null
cp "$MODDIR/module.prop" "$DIR/" 2>/dev/null
cp "$MODDIR/imsprofile_0.xml.orig" "$DIR/" 2>/dev/null

getprop > "$DIR/getprop.txt" 2>/dev/null
settings list global > "$DIR/settings-global.txt" 2>/dev/null
dumpsys telephony.registry > "$DIR/telephony-registry.txt" 2>/dev/null
content query --uri content://telephony/carriers \
    --projection _id:name:numeric:mcc:mnc:apn:type:current > "$DIR/apns.txt" 2>/dev/null
content query --uri content://com.sec.ims.settings/imsswitch > "$DIR/imsswitch.txt" 2>/dev/null
content query --uri content://com.sec.ims.settings/profile/1 > "$DIR/imsprofile-1.txt" 2>/dev/null
ip addr > "$DIR/ip-addr.txt" 2>/dev/null

logcat -b radio -d -v time 2>/dev/null | tail -3000 > "$DIR/radio.log"
logcat -b main -d -v time 2>/dev/null | \
    grep -iE 'ImsSms|ImsRegistration|SmsServiceModule|RegiMgr|DCT-C|RILJ|SmsDispatcher' | \
    tail -3000 > "$DIR/ims-sms-main.log"

cd /data/local/tmp || exit 1
BASE=$(basename "$DIR")
if tar -czf "$BASE.tar.gz" "$BASE" 2>/dev/null; then
    rm -rf "$DIR"
    echo "diagnostics: /data/local/tmp/$BASE.tar.gz"
else
    echo "diagnostics: $DIR (tar.gz failed; pull the directory)"
fi
