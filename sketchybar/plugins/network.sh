#!/usr/bin/env bash

# Network status: the Wi-Fi name, Ethernet, or why there is no connection
# The icons are SF Symbols, so they need the SF Pro font (brew install --cask font-sf-pro)

WIFI=􀙇         # wifi
WIFI_OFF=􀙈     # wifi.slash
WIFI_NO_NET=􀙥  # wifi.exclamationmark
ETHERNET=􀴞     # cable.connector.horizontal
OFFLINE=􁣡      # network.slash

source "$CONFIG_DIR/colors.sh"

# macOS 14.4+ redacts the SSID in networksetup, ipconfig and system_profiler,
# but it is still in the last scan record cached in the System Configuration store
wifi_ssid() {
  osascript -l JavaScript - "$1" 2>/dev/null <<'EOF'
ObjC.import('SystemConfiguration')
function run(argv) {
  try {
    const store = $.SCDynamicStoreCreate(null, $('sketchybar'), null, null)
    const state = ObjC.castRefToObject($.SCDynamicStoreCopyValue(store, $(`State:/Network/Interface/${argv[0]}/AirPort`)))
    return $.NSKeyedUnarchiver.unarchiveObjectWithData(state.objectForKey('CachedScanRecord')).objectForKey('SSID_STR').js
  } catch (e) {
    return ''
  }
}
EOF
}

PORTS="$(networksetup -listallhardwareports)"
WIFI_DEVICE="$(awk '/^Hardware Port: Wi-Fi$/ {getline; print $2}' <<< "$PORTS")"
HARDWARE_DEVICES="$(awk '/^Device:/ {print $2}' <<< "$PORTS")"

# Interfaces with a working connection, in service order: the first physical one
# (skipping VPN tunnels and the like) is the one macOS is actually using
PRIMARY_INTERFACE=""
for interface in $(scutil --nwi | sed -n 's/^Network interfaces: //p'); do
  if grep -qx "$interface" <<< "$HARDWARE_DEVICES"; then
    PRIMARY_INTERFACE="$interface"
    break
  fi
done

if [ -n "$PRIMARY_INTERFACE" ] && [ "$PRIMARY_INTERFACE" = "$WIFI_DEVICE" ]; then
  SSID="$(wifi_ssid "$WIFI_DEVICE")"
  ICON=$WIFI COLOR=$TEXT LABEL="${SSID:-Wi-Fi}"
elif [ -n "$PRIMARY_INTERFACE" ]; then
  ICON=$ETHERNET COLOR=$TEXT LABEL="Ethernet"
elif [ -z "$WIFI_DEVICE" ]; then
  ICON=$OFFLINE COLOR=$RED LABEL="Offline"
elif networksetup -getairportpower "$WIFI_DEVICE" | grep -q 'On$'; then
  ICON=$WIFI_NO_NET COLOR=$YELLOW LABEL="Non connesso"
else
  ICON=$WIFI_OFF COLOR=$RED LABEL="Wi-Fi off"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
