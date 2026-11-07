#!/system/bin/sh
# SCR-01 SMS enable — v2.1 (cinnamon theme overlay + China Telecom APN fix).
#
# Why cinnamon overlay: on this device root is only available LATE (after SCRoot
# re-root, which is after zygote). So any overlay mount is too late to reach
# zygote's preloaded framework resources, and a soft reboot (zygote restart)
# BREAKS the framework (SCRoot's one-time credential hook is lost). Instead we
# use a mutable THEME overlay (AccentColorCinnamon) + "cmd overlay enable", which
# broadcasts ACTION_OVERLAY_CHANGED and makes the phone + permissioncontroller
# processes re-read config_sms_capable=true after a restart. This is a runtime
# operation — no soft reboot, no partition write.
#
# v2.1 changes:
#  - China Telecom (46011) is matched by the APN engine with operator=46003
#    (DcTracker buildWaitingApns), so an IMS APN with numeric 46011 never enters
#    the candidate list -> no P-CSCF -> IMS never registers -> SMS "no service".
#    We now also create SCR01_SMS_IMS_46003 for 46011 SIMs.
#  - Strip "ims" from any built-in APN (e.g. China Telecom "cmnet") so it does
#    not swallow the IMS PDN and leave the device without a P-CSCF.

MODDIR=${0%/*}
LOG="$MODDIR/boot-completed.log"
NSENTER=/system/bin/nsenter

SMS_APP=org.fossify.messages
CINN_TARGET=/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk
SMS_RRO="$MODDIR/payload/scr01-dynamic-sms.apk"
ROLE_PROBE="$MODDIR/payload/SmsRoleProbe.dex"
CINN_SHA=7a206d842ad6baa60a22e10df8b154dc92b76e4ee3f5006adfbca9c89e2d8f19
RRO_SHA=5e6d42544f9c03901206a633c967e63836eb76bf4e28fff6c6044b21e043ec6d

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
log "boot-completed start (v2.1)"

# 1. bind-mount the SMS RRO over the cinnamon overlay (self-check, fail-closed).
psha=$(sha256sum "$SMS_RRO" 2>/dev/null | cut -d' ' -f1)
if [ "$psha" != "$RRO_SHA" ]; then
    log "FAIL sms rro sha mismatch ($psha)"; exit 1
fi
tsha=$("$NSENTER" -t 1 -m -- sha256sum "$CINN_TARGET" 2>/dev/null | cut -d' ' -f1)
case "$tsha" in
    "$RRO_SHA") log "cinnamon already mounted";;
    "$CINN_SHA")
        if "$NSENTER" -t 1 -m -- mount --bind "$SMS_RRO" "$CINN_TARGET" 2>>"$LOG"; then
            log "cinnamon mounted"
        else
            log "FAIL cinnamon mount"; exit 1
        fi
        ;;
    "") log "FAIL cannot read cinnamon sha"; exit 1;;
    *) log "FAIL unexpected cinnamon sha ($tsha)"; exit 1;;
esac

# 2. enable the cinnamon overlay (broadcasts ACTION_OVERLAY_CHANGED).
cmd overlay enable --user 0 com.android.theme.color.cinnamon >>"$LOG" 2>&1
log "cinnamon overlay enabled"

# 3. restart phone so SMSDispatcher/InboundSmsHandler re-read config_sms_capable=true.
pidof com.android.phone | xargs -r kill -TERM 2>/dev/null
sleep 6

# 4. restart permissioncontroller so it re-evaluates the SMS role availability.
pidof com.google.android.permissioncontroller | xargs -r kill 2>/dev/null
sleep 4

# 5. force android.app.role.SMS into the available-role list (idempotent).
if [ -f "$ROLE_PROBE" ]; then
    CLASSPATH="$ROLE_PROBE" app_process /system/bin SmsRoleProbe enable >>"$LOG" 2>&1
    log "SMS role forced into list"
else
    log "WARN no role probe payload"
fi

# 6. grant the SMS role to the default SMS app (idempotent, with retry).
grant_ok=0
i=0
while [ "$i" -lt 5 ]; do
    if cmd role add-role-holder --user 0 android.app.role.SMS "$SMS_APP" >>"$LOG" 2>&1; then
        grant_ok=1; break
    fi
    i=$((i + 1)); sleep 2
done
if [ "$grant_ok" = 1 ]; then
    log "SMS role granted to $SMS_APP"
else
    log "WARN SMS role grant failed after retries"
fi

# 7. IMS bearer: dynamic IMS APN + volte/smsip switches (idempotent).
MNCMCC=$(getprop gsm.sim.operator.numeric 2>/dev/null)
[ -n "$MNCMCC" ] || MNCMCC=$(getprop gsm.operator.numeric 2>/dev/null)

# China Telecom quirk: the APN engine matches this SIM with operator=46003
# (its "home" PLMN), not the 46011 printed by getprop. Emit both so whichever
# one the engine uses, an IMS APN exists.
FNUMERICS="$MNCMCC"
[ "$MNCMCC" = "46011" ] && FNUMERICS="46011 46003"

for NUM in $FNUMERICS; do
    [ -n "$NUM" ] || continue
    MCC=${NUM%???}
    MNC=${NUM#???}
    APN_NAME="SCR01_SMS_IMS_${NUM}"
    has=$(content query --uri content://telephony/carriers 2>/dev/null | grep -c "name=${APN_NAME}" || true)
    if [ "$has" = "0" ]; then
        content insert --uri content://telephony/carriers \
            --bind name:s:"$APN_NAME" --bind apn:s:ims --bind type:s:ims \
            --bind mcc:s:"$MCC" --bind mnc:s:"$MNC" --bind numeric:s:"$NUM" \
            --bind protocol:s:IPV4V6 --bind roaming_protocol:s:IPV4V6 \
            --bind carrier_enabled:i:1 >>"$LOG" 2>&1
        log "inserted IMS APN $APN_NAME"
    fi
done

# 7b. strip "ims" from any built-in APN (e.g. "cmnet") so that it does not
# steal the IMS PDN. Without this the phone attaches IMS to a data APN that
# never receives a P-CSCF, and IMS stays unregistered.
content query --uri content://telephony/carriers --projection _id:name:type 2>/dev/null | \
while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in
        *type=*ims*) ;;
        *) continue;;
    esac
    apn_name=$(printf '%s' "$row" | sed -n 's/.*name=\(.*\), type=.*/\1/p')
    case "$apn_name" in
        SCR01_SMS_IMS_*) continue;;
    esac
    apn_id=$(printf '%s' "$row" | sed -n 's/.*_id=\([0-9]*\).*/\1/p')
    apn_type=$(printf '%s' "$row" | sed -n 's/.*type=//p')
    [ -n "$apn_id" ] || continue
    [ -n "$apn_type" ] || continue
    new_type=$(printf '%s' "$apn_type" | tr ',' '\n' | grep -vx 'ims' | tr '\n' ',' | sed 's/,$//')
    [ -n "$new_type" ] || continue
    [ "$new_type" = "$apn_type" ] && continue
    content update --uri content://telephony/carriers --bind type:s:"$new_type" --where "_id=$apn_id" >>"$LOG" 2>&1
    log "stripped ims from APN $apn_id ($apn_type -> $new_type)"
done

content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:smsip --bind enabled:b:true >>"$LOG" 2>&1
content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:volte --bind enabled:b:true >>"$LOG" 2>&1
log "volte+smsip enabled"

# 8. sync the legacy default-SMS setting.
settings put secure sms_default_application "$SMS_APP" >>"$LOG" 2>&1

log "boot-completed done"
