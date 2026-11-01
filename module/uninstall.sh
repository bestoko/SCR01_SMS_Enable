#!/system/bin/sh
# SCR-01 SMS enable — rollback (uninstall). Idempotent, fail-safe.
MODDIR=${0%/*}
LOG="$MODDIR/uninstall.log"
NSENTER=/system/bin/nsenter
CINN_TARGET=/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk
ROLE_PROBE="$MODDIR/payload/SmsRoleProbe.dex"
SMS_APP=org.fossify.messages
CINN_SHA=7a206d842ad6baa60a22e10df8b154dc92b76e4ee3f5006adfbca9c89e2d8f19
RRO_SHA=5e6d42544f9c03901206a633c967e63836eb76bf4e28fff6c6044b21e043ec6d

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
log "uninstall start"

# 1. disable cinnamon overlay + unmount the SMS RRO (restore original).
cmd overlay disable --user 0 com.android.theme.color.cinnamon >>"$LOG" 2>&1
tsha=$("$NSENTER" -t 1 -m -- sha256sum "$CINN_TARGET" 2>/dev/null | cut -d' ' -f1)
if [ "$tsha" = "$RRO_SHA" ]; then
    "$NSENTER" -t 1 -m -- umount "$CINN_TARGET" 2>/dev/null || \
        "$NSENTER" -t 1 -m -- umount -l "$CINN_TARGET" 2>/dev/null
    nsha=$("$NSENTER" -t 1 -m -- sha256sum "$CINN_TARGET" 2>/dev/null | cut -d' ' -f1)
    if [ "$nsha" = "$CINN_SHA" ]; then
        log "cinnamon restored to stock"
    else
        log "WARN post-unmount cinnamon sha ($nsha)"
    fi
else
    log "cinnamon not mounted (sha=$tsha)"
fi

# 2. remove SMS role holder (best-effort; SmsRoleProbe restore is authoritative).
cmd role remove-role-holder --user 0 android.app.role.SMS "$SMS_APP" >>"$LOG" 2>&1 || true

# 3. remove android.app.role.SMS from the available-role list.
if [ -f "$ROLE_PROBE" ]; then
    CLASSPATH="$ROLE_PROBE" app_process /system/bin SmsRoleProbe restore >>"$LOG" 2>&1
fi
log "SMS role removed"

# 4. remove IMS APN(s) created by this module (name prefix SCR01_SMS_IMS_).
for apn_id in $(content query --uri content://telephony/carriers 2>/dev/null | \
    sed -n 's/.*_id=\([0-9][0-9]*\).*name=SCR01_SMS_IMS_.*/\1/p'); do
    content delete --uri content://telephony/carriers --where "_id=${apn_id}" >>"$LOG" 2>&1
done
log "IMS APN cleanup done"

# 5. disable volte + smsip.
content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:volte --bind enabled:b:false >>"$LOG" 2>&1
content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:smsip --bind enabled:b:false >>"$LOG" 2>&1
log "volte+smsip disabled"

log "uninstall done"
