SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

TOTAL=8
STEP=0

progress() {
  STEP=$((STEP + 1))
  ui_print "$(printf '  [%d/%d] %s' "$STEP" "$TOTAL" "$1")"
}

detail() {
  ui_print "         $1"
}

print_modname() {
  ui_print "****************************************"
  ui_print "            LTE_ON_LOS   v1"
  ui_print "       Get cell on ur T295!"
  ui_print "      on LineageOS 22.2 (A15)"
  ui_print "****************************************"
  ui_print ""
}

on_install() {
  progress "Checking target device"
  _plat=$(getprop ro.board.platform)
  _hw=$(getprop ro.hardware)
  if [ "$_plat" = "msm8937" ]; then
    detail "platform msm8937 / $_hw - match"
  else
    detail "WARNING: platform is '$_plat', not msm8937."
    detail "This module targets SM-T295 only; it may"
    detail "not work on your device."
  fi
  detail "android $(getprop ro.build.version.release)"

  progress "Extracting module files"
  unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2

  progress "Measuring payload"
  _l64=$(ls -1 $MODPATH/system/vendor/lib64 2>/dev/null | wc -l)
  _l32=$(ls -1 $MODPATH/system/vendor/lib 2>/dev/null | wc -l)
  _apk=$(find $MODPATH/system -name '*.apk' 2>/dev/null | wc -l)
  _xml=$(find $MODPATH/system -name '*.xml' 2>/dev/null | wc -l)
  detail "$_l64 libraries in vendor/lib64"
  detail "$_l32 libraries in vendor/lib"
  detail "$_apk apps (Dialer / Messages / Stk / SIM)"
  detail "$_xml config + permission files"

  progress "Applying permissions"
  set_perm_recursive $MODPATH 0 0 0755 0644
  set_perm $MODPATH/service.sh 0 0 0755
  set_perm $MODPATH/system/vendor/bin/hw/rild 0 1001 0755
  set_perm $MODPATH/system/vendor/bin/netmgrd 0 1001 0755
  set_perm $MODPATH/system/vendor/bin/secril_config_svc 0 1001 0755
  detail "service.sh + rild/netmgrd setuid radio"

  progress "Verifying core files"
  for _f in \
    module.prop \
    service.sh \
    system.prop \
    system/vendor/etc/vintf/manifest/t295_radio_manifest.xml \
    system/vendor/etc/data/netmgr_config.xml \
    system/vendor/lib64/libsec-ril.so ; do
    if [ -f "$MODPATH/$_f" ]; then
      detail "OK   $_f"
    else
      detail "MISSING  $_f"
    fi
  done

  progress "Checking radio + data binaries"
  for _b in \
    system/vendor/bin/hw/rild \
    system/vendor/bin/netmgrd \
    system/vendor/bin/secril_config_svc \
    system/vendor/lib64/android.system.net.netd@1.1.so \
    system/vendor/lib64/libnetd_client.so ; do
    if [ -f "$MODPATH/$_b" ]; then
      detail "OK   $_b"
    else
      detail "MISSING  $_b"
    fi
  done

  progress "Registering boot-time service"
  detail "service.sh runs at every boot:"
  detail "  1. launches rild + netmgrd"
  detail "  2. fixes /dev/socket/netmgr ownership"
  detail "  3. flags a preferred APN for your SIM"

  progress "Done"
  ui_print ""
  ui_print "  REBOOT to apply."
  ui_print ""
  ui_print "  After reboot, verify with:"
  ui_print "    cat /data/local/tmp/t295_apn.log"
  ui_print "    ip addr show rmnet_data0"
  ui_print "    content query --uri content://telephony/carriers/preferapn"
  ui_print ""
}

set_permissions() {
  set_perm_recursive $MODPATH 0 0 0755 0644
  set_perm $MODPATH/service.sh 0 0 0755
  set_perm $MODPATH/system/vendor/bin/hw/rild 0 1001 0755
  set_perm $MODPATH/system/vendor/bin/netmgrd 0 1001 0755
  set_perm $MODPATH/system/vendor/bin/secril_config_svc 0 1001 0755
}