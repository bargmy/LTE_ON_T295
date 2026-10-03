#!/system/bin/sh
MODDIR=${0%/*}

# The T290 vendor's init config drops the ril-daemon/qmuxd service definitions
# because they require group oem_2901, which does not exist on Android 13. init
# never creates those services, so `start ril-daemon` is silently a no-op.
# We launch rild ourselves instead.
#
# setprop on rild.libpath is rejected by SELinux; resetprop on the Samsung
# properties is what actually makes RIL_Init run.
resetprop vendor.sec.rild.libpath /vendor/lib64/libsec-ril.so
resetprop vendor.sec.rild.libpath2 /vendor/lib64/libsec-ril.so
resetprop ro.radio.noril 0

# rild writes here immediately; must exist and be radio-owned (AID_RADIO=1001)
mkdir -p /data/vendor/radio
mkdir -p /data/vendor/secradio
chown 1001:1001 /data/vendor/radio
chown 1001:1001 /data/vendor/secradio
chmod 770 /data/vendor/radio
chmod 770 /data/vendor/secradio

chcon u:object_r:rild_exec:s0 /vendor/bin/hw/rild 2>/dev/null

# Let the modem subsystem and vendor HALs settle before the RIL touches them.
sleep 8

# QRTR name service. Without a QRTR-enabled kernel this exits immediately and
# harmlessly; with one, it is required for service lookups.
if [ -x /vendor/bin/qrtr-ns ]; then
    /vendor/bin/qrtr-ns >/data/local/tmp/qrtr-ns.log 2>&1 &
    sleep 2
fi

# Samsung/QCOM RIL.
#
# The kernel does NOT have QRTR (CONFIG_QRTR=n), but that appears not to matter:
# the legacy IPC Router stack is present and populated (AF_MSM_IPC registered,
# modem_IPCRTR transport initialised, QMI services registered on the modem node).
# libqmi_cci.so carries both qcci_qrtr_ops and qcci_ipc_router_ops.
#
# Observed blocker was WDS config, not transport: with etc/data/netmgr_config.xml
# missing, rild logged "XML open error!", left phys_net_dev empty, and looped on
# "ConfEmbeddedData(): Failed to init Physical transport" / "Failed to set LLP mode
# to interface()". That config is supplied by this module.
if ! pidof rild >/dev/null 2>&1; then
    /vendor/bin/hw/rild >/data/local/tmp/rild.log 2>&1 &
fi

# netmgrd: the mobile-data path. Same root cause as rild above - the T290
# vendor's init config is dropped because it needs group oem_2901, so init never
# defines a netmgrd service and nothing ever starts it. The binary is present at
# /vendor/bin/netmgrd but was idle, which is why LTE showed in the status bar
# while no data interface was ever brought up.
#
# netmgrd is independent of rild, so it can start immediately; it does not need
# to wait for the modem. It creates /dev/socket/netmgrd, which the telephony
# framework binds to.
# netmgrd needs two directories that no init service would have created:
#   /dev/socket/netmgr  - its control sockets. The directory must be root:inet
#                         mode 771; with the wrong ownership netmgrd aborts
#                         immediately with "netmgr_unix_listener_init failed".
#   /data/vendor/netmgr  - recovery_info + log.txt.
mkdir -p /dev/socket/netmgr
chown root:inet /dev/socket/netmgr 2>/dev/null
chmod 771 /dev/socket/netmgr
mkdir -p /data/vendor/netmgr/recovery
chmod 771 /data/vendor/netmgr 2>/dev/null

chcon u:object_r:netmgrd_exec:s0 /vendor/bin/netmgrd 2>/dev/null
if ! pidof netmgrd >/dev/null 2>&1; then
    /vendor/bin/netmgrd >/data/local/tmp/netmgrd.log 2>&1 &
fi

# ---------------------------------------------------------------------------
# Mobile data: preferred-APN activation.
#
# Confirmed failure mode this fixes: the carriers table held a perfectly good
# Internet APN (type=default,supl, carrier_enabled=1, current=1) yet no APN was
# flagged as the subscription's preferred one, and DataProfileManager reported
# NO_SUITABLE_DATA_PROFILE forever. No SETUP_DATA_CALL was ever issued, so
# rmnet_data0 stayed down despite rild, netmgrd and LTE registration all being
# healthy. Writing that same APN through content://telephony/carriers/preferapn
# made Android immediately build a usable DataProfile, issue SETUP_DATA_CALL and
# bring the interface up.
#
# Deliberately carrier-agnostic: nothing here is specific to one operator. The
# SIM's MCC+MNC is read at runtime and matched against the APN database.
#
# Rules obeyed here:
#   * only content://telephony/... - never raw sqlite3 on telephony.db
#   * never invents an APN; if the database has none for this SIM, log and stop
#   * never touches the mobile_data setting - that is the user's switch
#   * bounded retry purely for provider/subscription readiness, stops on success
# ---------------------------------------------------------------------------
APN_LOG=/data/local/tmp/t295_apn.log

apn_log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $APN_LOG; }

# Ready once TelephonyProvider answers and the SIM's operator is known.
apn_ready() {
    [ -n "$(getprop gsm.sim.operator.numeric)" ] || return 1
    content query --user 0 --uri content://telephony/carriers \
        --projection _id 2>/dev/null | grep -q 'Row:'
}

# Pick the best usable Internet APN for $1 (MCC+MNC).
# Prefers: carrier_enabled=1, type includes default, current=1 first.
pick_apn_id() {
    _op=$1
    _rows=/data/local/tmp/.t295_apn_rows
    _pref=""
    _def=""
    content query --user 0 --uri content://telephony/carriers \
        --where "numeric='$_op'" \
        --projection _id:type:current:carrier_enabled > "$_rows" 2>/dev/null

    while IFS= read -r _l; do
        case "$_l" in *Row:*) ;; *) continue ;; esac
        _id=$(echo "$_l" | sed -n 's/.*_id=\([0-9][0-9]*\).*/\1/p')
        _tp=$(echo "$_l" | sed -n 's/.*type=\(.*\), current=.*/\1/p')
        _cu=$(echo "$_l" | sed -n 's/.*, current=\([0-9]*\).*/\1/p')
        _en=$(echo "$_l" | sed -n 's/.*carrier_enabled=\([0-9]*\).*/\1/p')
        [ -n "$_id" ] || continue
        [ "$_en" = "1" ] || continue
        # type may be a comma-separated list and may use the '*' wildcard
        case ",$_tp," in
            *,default,*|*'*'*) ;;
            *) continue ;;
        esac
        [ -z "$_def" ] && _def=$_id
        [ "$_cu" = "1" ] && [ -z "$_pref" ] && _pref=$_id
    done < "$_rows"
    rm -f "$_rows"

    if [ -n "$_pref" ]; then echo "$_pref"; return 0; fi
    if [ -n "$_def" ]; then echo "$_def"; return 0; fi
    return 1
}

set_preferred_apn() {
    _op=$(getprop gsm.sim.operator.numeric)
    [ -n "$_op" ] || { apn_log "SIM operator unknown, aborting"; return 1; }

    _id=$(pick_apn_id "$_op")
    if [ -z "$_id" ]; then
        apn_log "no suitable APN found for operator $_op - leaving APN state untouched"
        return 1
    fi

    content update --user 0 --uri content://telephony/carriers/preferapn \
        --bind apn_id:i:$_id >/dev/null 2>&1 || {
        apn_log "preferapn update failed for apn_id=$_id (operator $_op)"
        return 1
    }
    apn_log "preferred APN set: apn_id=$_id operator=$_op"
    return 0
}

: > $APN_LOG
apn_log "service.sh start"
N=0
while [ $N -lt 24 ]; do
    if apn_ready; then
        if set_preferred_apn; then break; fi
    fi
    N=$((N+1))
    sleep 5
done
[ $N -ge 24 ] && apn_log "gave up waiting for TelephonyProvider/SIM readiness"

# mobile_data is intentionally left alone: whether cellular data is on is the
# user's choice, not something a module should decide.