#!/system/bin/sh
# SCR-01 SMS enable — v2.2 (cinnamon overlay + APN database + IMS profile patch).
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
# v2.2:
#  - Payload now carries a compact APN database (payload/apns.tsv, generated
#    from LineageOS android_vendor_apn, Apache-2.0). For the SIM PLMN and the
#    registered PLMN the module inserts the missing "default" and "ims" APNs, so
#    carriers the SCR-01's KDDI-only apns-conf.xml does not know about work too.
#  - IMS profile patch is retried and verified; the IMS service is only
#    restarted when the profile actually changed.
#  - Log rotation (128 KiB, one .1 backup) + a collect-logs.sh helper.
#  - Mobile data / roaming data are never forced on: Samsung's IMS PDN is
#    always-on and carries SMS even with mobile_data=0 and data_roaming=0.

MODDIR=${0%/*}
LOG="$MODDIR/boot-completed.log"
LOG_MAX=131072
NSENTER=/system/bin/nsenter

SMS_APP=org.fossify.messages
CINN_TARGET=/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk
SMS_RRO="$MODDIR/payload/scr01-dynamic-sms.apk"
ROLE_PROBE="$MODDIR/payload/SmsRoleProbe.dex"
APN_DB="$MODDIR/payload/apns.tsv"
PROFILE_XML=/data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml
CINN_SHA=7a206d842ad6baa60a22e10df8b154dc92b76e4ee3f5006adfbca9c89e2d8f19
RRO_SHA=5e6d42544f9c03901206a633c967e63836eb76bf4e28fff6c6044b21e043ec6d

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Keep the log small: one 128 KiB file + one .1 backup.
rotate_logs() {
    if [ -f "$LOG" ]; then
        sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
        [ "$sz" -gt "$LOG_MAX" ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
    fi
    [ -f "$LOG.1" ] && rm -f "$LOG.2" "$LOG.old" 2>/dev/null
}
rotate_logs
log "boot-completed start (v2.2) uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"

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

# ---------------------------------------------------------------------------
# 7. Network / IMS configuration (needs a loaded SIM).
# ---------------------------------------------------------------------------
split_plmn() {
    PN=$1
    case ${#PN} in
        5) PMCC=${PN%??}; PMNC=${PN#???};;
        6) PMCC=${PN%???}; PMNC=${PN#???};;
        *) PMCC=""; PMNC="";;
    esac
}

# True if any APN of $1 (numeric) already handles APN type $2.
apn_type_exists() {
    content query --uri content://telephony/carriers --projection numeric:type 2>/dev/null \
        | grep -q "numeric=$1, type=.*$2"
}

# Print the best non-MVNO APN row for <numeric> <type> from the APN database.
# Prefers an APN whose name starts with/contains "internet" (Spark, etc.).
apn_lookup() {
    [ -f "$APN_DB" ] || return 0
    awk -F'\t' -v p="$1" -v t="$2" '
        $1 == p && $9 == "" {
            n = split($6, a, ",")
            for (i = 1; i <= n; i++) {
                if (a[i] == t) {
                    if (best == "" || $5 ~ /internet/) best = $0
                    if ($5 ~ /internet/) exit
                }
            }
        }
        END { if (best != "") print best }
    ' "$APN_DB"
}

# Insert an APN from the built-in database. <numeric> <type>
ensure_apn_from_db() {
    E_NUM=$1; E_TYPE=$2
    if apn_type_exists "$E_NUM" "$E_TYPE"; then
        log "APN $E_NUM/$E_TYPE already present"
        return 0
    fi
    E_ROW=$(apn_lookup "$E_NUM" "$E_TYPE")
    if [ -z "$E_ROW" ]; then
        log "APN DB: no $E_NUM/$E_TYPE row"
        return 1
    fi
    OLDIFS=$IFS
    IFS='	'
    set -- $E_ROW
    IFS=$OLDIFS
    E_MCC=$2; E_MNC=$3; E_NAME=$4; E_APN=$5; E_ATYPE=$6; E_PROTO=$7; E_RPROTO=$8
    [ -n "$E_PROTO" ] || E_PROTO=IP
    [ -n "$E_RPROTO" ] || E_RPROTO=$E_PROTO
    content insert --uri content://telephony/carriers \
        --bind name:s:"$E_NAME" --bind apn:s:"$E_APN" --bind type:s:"$E_ATYPE" \
        --bind mcc:s:"$E_MCC" --bind mnc:s:"$E_MNC" --bind numeric:s:"$E_NUM" \
        --bind protocol:s:"$E_PROTO" --bind roaming_protocol:s:"$E_RPROTO" \
        --bind carrier_enabled:i:1 >>"$LOG" 2>&1
    log "APN inserted from DB: $E_NUM $E_NAME ($E_ATYPE / $E_APN)"
}

# Generic IMS APN fallback for carriers absent from the database.
ensure_ims_apn() {
    I_NUM=$1
    ensure_apn_from_db "$I_NUM" "ims" && return 0
    split_plmn "$I_NUM"; [ -n "$PMCC" ] || return 1
    apn_type_exists "$I_NUM" "ims" && return 0
    content insert --uri content://telephony/carriers \
        --bind name:s:"SCR01_SMS_IMS_$I_NUM" --bind apn:s:ims --bind type:s:ims \
        --bind mcc:s:"$PMCC" --bind mnc:s:"$PMNC" --bind numeric:s:"$I_NUM" \
        --bind protocol:s:IPV4V6 --bind roaming_protocol:s:IPV4V6 \
        --bind carrier_enabled:i:1 >>"$LOG" 2>&1
    log "IMS APN inserted (fallback): $I_NUM"
}

# Patch the active Samsung IMS profile, then restart IMS only if it changed.
patch_ims_profile() {
    P_XML=$1
    if [ ! -f "$P_XML" ]; then
        log "WARN IMS profile not found: $P_XML"
        return 1
    fi
    P_BEFORE=$(sha256sum "$P_XML" 2>/dev/null | cut -d' ' -f1)
    sed \
        -e 's/&quot;support_roaming&quot;:false/\&quot;support_roaming\&quot;:true/g' \
        -e 's/&quot;ipver&quot;:&quot;ipv6&quot;/\&quot;ipver\&quot;:\&quot;ipv4v6\&quot;/g' \
        -e 's/&quot;enc_algo&quot;:&quot;aes-cbc&quot;/\&quot;enc_algo\&quot;:\&quot;all\&quot;/g' \
        -e 's/&quot;services&quot;:\[&quot;mmtel&quot;,&quot;mmtel-video&quot;\]/\&quot;services\&quot;:[\&quot;mmtel\&quot;,\&quot;mmtel-video\&quot;,\&quot;smsip\&quot;]/g' \
        "$P_XML" > /data/local/tmp/imsprofile_patched.xml 2>>"$LOG"
    if [ ! -s /data/local/tmp/imsprofile_patched.xml ]; then
        log "FAIL IMS profile sed produced an empty file"
        return 1
    fi
    if ! grep -q '&quot;smsip&quot;' /data/local/tmp/imsprofile_patched.xml; then
        log "WARN IMS profile patch: smsip marker not found (already different?)"
    fi
    P_AFTER=$(sha256sum /data/local/tmp/imsprofile_patched.xml 2>/dev/null | cut -d' ' -f1)
    cp -f /data/local/tmp/imsprofile_patched.xml "$P_XML"
    chown system:system "$P_XML" 2>>"$LOG"
    chmod 660 "$P_XML" 2>>"$LOG"
    restorecon "$P_XML" 2>>"$LOG"
    if [ "$P_BEFORE" != "$P_AFTER" ]; then
        imspid=$(pidof com.sec.imsservice 2>/dev/null)
        if [ -n "$imspid" ]; then
            kill -9 $imspid 2>>"$LOG"
            log "IMS profile changed; IMS service restarted (pid $imspid)"
        else
            log "IMS profile changed; IMS service not running"
        fi
    else
        log "IMS profile already patched; no restart needed"
    fi
    return 0
}

SIM_STATE=$(getprop gsm.sim.state 2>/dev/null)
if [ "$SIM_STATE" != "LOADED" ]; then
    log "no SIM loaded (state=$SIM_STATE); skip network/IMS setup"
else
    HOME_PLMN=$(getprop gsm.sim.operator.numeric 2>/dev/null)
    REG_PLMN=$(getprop gsm.operator.numeric 2>/dev/null)
    IS_ROAMING=$(getprop gsm.operator.isroaming 2>/dev/null)
    log "SIM=$HOME_PLMN REG=$REG_PLMN roaming=$IS_ROAMING"
    log "mobile_data=$(settings get global mobile_data) data_roaming=$(settings get global data_roaming)"

    [ -f "$APN_DB" ] && log "APN database rows: $(wc -l < "$APN_DB")" || log "WARN APN database missing: $APN_DB"

    # China Telecom quirk: a 46011 SIM is matched by the APN engine with 46003
    # (EHPLMN), so handle both PLMNs. v2.1 had this; the v2.2 rewrite dropped it.
    PLMN_LIST="$HOME_PLMN $REG_PLMN"
    case " $PLMN_LIST " in *" 46011 "*) PLMN_LIST="$PLMN_LIST 46003";; esac
    case " $PLMN_LIST " in *" 46003 "*) PLMN_LIST="$PLMN_LIST 46011";; esac

    # 7a. Strip "ims" from built-in APNs FIRST. If IMS APNs are ensured before
    # this step, apn_type_exists sees the built-in "default,...,ims,..." row,
    # skips the dedicated IMS APN, and this strip then leaves the device with
    # no IMS APN at all (issue #1, China Telecom 46011/46003).
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

    # 7b. IMS APNs for every PLMN the APN engine may match (dedup).
    SEEN=""
    for NUM in $PLMN_LIST; do
        [ -n "$NUM" ] || continue
        case " $SEEN " in *" $NUM "*) continue;; esac
        SEEN="$SEEN $NUM"
        ensure_ims_apn "$NUM" || log "WARN no IMS APN for $NUM"
    done

    # 7c. Default/data APNs from the built-in database; known extras as fallback.
    SEEN=""
    for NUM in $PLMN_LIST; do
        [ -n "$NUM" ] || continue
        case " $SEEN " in *" $NUM "*) continue;; esac
        SEEN="$SEEN $NUM"
        ensure_apn_from_db "$NUM" "default" || log "APN DB: no default APN for $NUM"
    done
    case "$HOME_PLMN" in
        53005)
            apn_type_exists "$HOME_PLMN" "default" || \
                ensure_apn_from_db "$HOME_PLMN" "default" || \
                log "WARN no Skinny default APN"
            ;;
    esac

    # 7d. enable the Samsung IMS switches.
    content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:smsip --bind enabled:b:true >>"$LOG" 2>&1
    content update --uri content://com.sec.ims.settings/imsswitch --bind service:s:volte --bind enabled:b:true >>"$LOG" 2>&1
    log "volte+smsip enabled"

    # 7e. patch the active IMS profile (retry while the IMS service rewrites it).
    i=0
    while [ ! -f "$PROFILE_XML" ] && [ "$i" -lt 12 ]; do
        sleep 5; i=$((i + 1))
    done
    [ -f "$MODDIR/imsprofile_0.xml.orig" ] || \
        cp -f "$PROFILE_XML" "$MODDIR/imsprofile_0.xml.orig" 2>/dev/null
    patch_ims_profile "$PROFILE_XML" || log "WARN IMS profile patch skipped"
fi

# 8. sync the legacy default-SMS setting.
settings put secure sms_default_application "$SMS_APP" >>"$LOG" 2>&1

log "boot-completed done"
