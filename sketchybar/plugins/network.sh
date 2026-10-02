#!/usr/bin/env bash

# Network: the network item shows the icon of the connection, followed by the Wi-Fi name, Ethernet,
# or why there is none in network_name, and by the band of the Wi-Fi in network_band; network_vpn,
# before them in the same pill, the shield while a VPN is on, followed by its name in
# network_vpn_name. The names aren't on the display with the notch (see notch.sh). A click on any of
# them opens the popup of the connection bracket: the IP address of the Mac, the public one, the
# router and the VPN; then Ethernet and Wi-Fi, each with a row that turns it off or on, and the Wi-Fi
# networks around the Mac, those saved on it first, where a click joins one; last Impostazioni Rete….
# Since macOS 14.4 only an app that may use Location Services gets the names of the Wi-Fi networks
# and can join one: helpers/wifi_networks.app, which sketchybarrc starts, triggers
# wifi_networks_change with them (NETWORKS) whenever they change, and helpers/wifi_networks asks it
# for a new scan or to join a network, which comes back with the same event (JOINED, RESULT).
# The bar items run this with no arguments, the popup rows with wifi <on|off>, ethernet <on|off>
# <service>, join <name>, location or settings, or with current
# The icons are SF Symbols, so they need the SF Pro font (brew install --cask font-sf-pro)

WIFI=􀙇         # wifi
WIFI_OFF=􀙈     # wifi.slash
WIFI_NO_NET=􀙥  # wifi.exclamationmark
ETHERNET=􀴞     # cable.connector.horizontal
OFFLINE=􁣡      # network.slash
LOCK=􀎡         # lock.fill
NETWORK_ICONS="$CONFIG_DIR/helpers/network_icons"
HELPER="$CONFIG_DIR/helpers/wifi_networks"
NETWORKS_FILE="${TMPDIR:-/tmp}/sketchybar_wifi_networks"
JOIN_FILE="${TMPDIR:-/tmp}/sketchybar_wifi_join"
PUBLIC_FILE="${TMPDIR:-/tmp}/sketchybar_public_ip"

source "$CONFIG_DIR/colors.sh"

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
LOCK_FONT="SF Pro:Semibold:11.0"
MIN_WIDTH=260
INSET=4         # between the rows and the edge of the popup, as in apple.sh
PADDING=8       # inside the rows
GAP=16          # between the two columns of a row
ICON_GAP=8      # between the icon and the name of a network
ROW_HEIGHT=24   # of a row, unless it sets its own
SECTION_GAP=10  # above Ethernet, Wi-Fi and Impostazioni Rete…
# The rows of the lists are always as many: the networks saved on the Mac, the others (the
# strongest ones) and the wired services
KNOWN=10
OTHERS=10
WIRED=3

ADDRESS_TITLE="Indirizzo IP"
PUBLIC_TITLE="IP pubblico"
ROUTER_TITLE="Router"
VPN_TITLE="VPN"
VPN_ADDRESS_TITLE="Indirizzo VPN"
NONE="Nessuno"
UNAVAILABLE="Non disponibile"
VPN_OFF="Non attiva"
TURN_ON="Attiva"
TURN_OFF="Disattiva"
CONNECTED_TEXT="connessa"
DISCONNECTED_TEXT="non connessa"
DISABLED_TEXT="disattivata"
KNOWN_TITLE="Reti conosciute"
OTHER_TITLE="Altre reti"
SEARCHING="Ricerca reti…"
LOCATION="Consenti la posizione per vedere le reti"
CONNECTING="Connessione…"
FAILED="Non riuscito"
SETTINGS="Impostazioni Rete…"

# The name of the Wi-Fi network and its band, separated by a tab, e.g. Casa\t5. macOS 14.4+ redacts
# the SSID in networksetup, ipconfig and system_profiler, and CoreWLAN gives it only to an app that
# may use the location, but it is still in the last scan record cached in the System Configuration
# store, with the channel. Its flags tell the band, as in the Apple80211 headers: 0x8 2.4 GHz, 0x10
# 5 GHz, 0x2000 6 GHz; without them the number of the channel does, up to 14 in the 2.4 GHz band
wifi_network() {
  osascript -l JavaScript - "$1" 2>/dev/null <<'EOF'
ObjC.import('SystemConfiguration')
function run(argv) {
  try {
    const store = $.SCDynamicStoreCreate(null, $('sketchybar'), null, null)
    const state = ObjC.castRefToObject($.SCDynamicStoreCopyValue(store, $(`State:/Network/Interface/${argv[0]}/AirPort`)))
    const record = $.NSKeyedUnarchiver.unarchiveObjectWithData(state.objectForKey('CachedScanRecord'))
    const number = key => Number(ObjC.unwrap(record.objectForKey(key))) || 0
    const flags = number('CHANNEL_FLAGS'), channel = number('CHANNEL')
    const band = flags & 0x2000 ? '6' : flags & 0x10 ? '5' : flags & 0x8 ? '2.4' : channel > 14 ? '5' : channel > 0 ? '2.4' : ''
    return `${record.objectForKey('SSID_STR').js}\t${band}`
  } catch (e) {
    return ''
  }
}
EOF
}

# address <interface>: its IPv4 address, from scutil --nwi
address() {
  awk -v interface="$1" '/^IPv6/ {exit} $3 == "flags" {found = $1 == interface} found && $1 == "address" {print $3; exit}' <<< "$NWI"
}

# router <interface>: the gateway of its default route. Each interface has one of its own, scoped
# to it, also when a VPN takes the default route of the Mac
router() {
  netstat -rnf inet | awk -v interface="$1" '$1 == "default" && $4 == interface {print $2; exit}'
}

# The wired services whose port is on the Mac, in the order of System Settings: <enabled>\t<device>\t
# <name>, where <enabled> is 0 or 1. Not the Wi-Fi nor the Thunderbolt Bridge. listnetworkserviceorder
# marks a disabled service with (*) in place of its number
wired_services() {
  local line name="" enabled device
  while IFS= read -r line; do
    case "$line" in
      "(Hardware Port: "*)
        device="${line##*, Device: }" device="${device%)}"
        [ -n "$name" ] && [ "$device" != "$WIFI_DEVICE" ] && [[ "$device" != bridge* ]] &&
          grep -qx "$device" <<< "$HARDWARE_DEVICES" && printf '%s\t%s\t%s\n' "$enabled" "$device" "$name"
        name=""
        ;;
      "(*) "*) enabled=0 name="${line#"(*) "}" ;;
      "("[0-9]*") "*) enabled=1 name="${line#*) }" ;;
    esac
  done < <(networksetup -listnetworkserviceorder)
}

# The state of the network: PRIMARY_INTERFACE, the one macOS is using, SSID, BAND and WIFI_POWER, and the
# VPN that is on: VPN_NAME and VPN_INTERFACE, if macOS knows it
read_network() {
  PORTS="$(networksetup -listallhardwareports)"
  WIFI_DEVICE="$(awk '/^Hardware Port: Wi-Fi$/ {getline; print $2}' <<< "$PORTS")"
  HARDWARE_DEVICES="$(awk '/^Device:/ {print $2}' <<< "$PORTS")"
  NWI="$(scutil --nwi)"
  CONNECTED="$(sed -n 's/^Network interfaces: //p' <<< "$NWI" | tr ' ' '\n')"

  # Interfaces with a working connection, in service order: the first physical one (skipping VPN
  # tunnels and the like) is the one macOS is actually using
  PRIMARY_INTERFACE=""
  local interface
  for interface in $CONNECTED; do
    if grep -qx "$interface" <<< "$HARDWARE_DEVICES"; then
      PRIMARY_INTERFACE="$interface"
      break
    fi
  done

  WIFI_POWER=off SSID="" BAND=""
  if [ -n "$WIFI_DEVICE" ]; then
    networksetup -getairportpower "$WIFI_DEVICE" | grep -q 'On$' && WIFI_POWER=on
    grep -qx "$WIFI_DEVICE" <<< "$CONNECTED" && IFS=$'\t' read -r SSID BAND <<< "$(wifi_network "$WIFI_DEVICE")"
  fi

  # The VPNs of System Settings and of the VPN apps are in scutil --nc, e.g.
  # * (Connected)  <id> VPN (com.wireguard.macos) "Ufficio"  [VPN/WireGuard]
  # and their tunnel, as those of the VPNs that macOS doesn't know, among the interfaces with a
  # working connection
  VPN_NAME="$(scutil --nc list | sed -nE 's/^. \(Connected\)[^"]*"([^"]*)".*/\1/p' | head -1)"
  VPN_INTERFACE="$(grep -m1 -E '^(utun|ipsec|ppp|tun|tap)[0-9]+$' <<< "$CONNECTED")"
  [ -n "$VPN_INTERFACE" ] && [ -z "$VPN_NAME" ] && VPN_NAME="VPN"

  # What the public address was read for, to tell when it is no longer the one of the connection
  CONNECTION="$PRIMARY_INTERFACE:$SSID:$VPN_NAME"
}

update_bar() {
  local band=(drawing=off)
  if [ -n "$PRIMARY_INTERFACE" ] && [ "$PRIMARY_INTERFACE" = "$WIFI_DEVICE" ]; then
    ICON=$WIFI COLOR=$TEXT LABEL="${SSID:-Wi-Fi}"
    # e.g. 2,4 GHz, with the decimal comma of the other texts
    [ -n "$BAND" ] && band=(drawing=on label="${BAND/./,} GHz")
  elif [ -n "$PRIMARY_INTERFACE" ]; then
    ICON=$ETHERNET COLOR=$TEXT LABEL="Ethernet"
  elif [ -z "$WIFI_DEVICE" ]; then
    ICON=$OFFLINE COLOR=$RED LABEL="Offline"
  elif [ "$WIFI_POWER" = on ]; then
    ICON=$WIFI_NO_NET COLOR=$YELLOW LABEL="Non connesso"
  else
    ICON=$WIFI_OFF COLOR=$RED LABEL="Wi-Fi off"
  fi

  local vpn=(drawing=off) vpn_name=(drawing=off)
  [ -n "$VPN_NAME" ] && vpn=(drawing=on) vpn_name=(drawing=on label="$VPN_NAME")
  sketchybar --set network icon="$ICON" icon.color="$COLOR" --set network_name label="$LABEL" \
             --set network_band "${band[@]}" \
             --set network_vpn "${vpn[@]}" --set network_vpn_name "${vpn_name[@]}"
}

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Medium 11 <text>... prints two widths, as in audio.sh. SketchyBar measures text
# only once it draws it, but the rows need a fixed width to line up the right column and to
# highlight a whole row
text_widths() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run(argv) {
  const widths = []
  let group = []
  for (const arg of [...argv, '--']) {
    if (arg !== '--') { group.push(arg); continue }
    const [name, size, ...texts] = group
    const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize(name, Number(size)), $.NSFontAttributeName)
    widths.push(Math.max(0, ...texts.map(text => Math.ceil($(text).sizeWithAttributes(font).width))))
    group = []
  }
  return widths.join(' ')
}
EOF
}

# quote <text>: the text in single quotes, for the shell that runs a script, as in audio.sh
quote() {
  local quote="'\\''"
  echo "'${1//\'/$quote}'"
}

# Each render lists all the popup rows, as in claude.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them,
# and subscribes the rows that light up under the mouse and run a script on click; render_popup
# empties them, since the click renders twice, the second time with the public address.
# The rows are always the same, the ones not needed hidden, as in battery.sh: so they are added only
# the first time. Removing a row under the mouse would close the popup (mouse.exited.global), and
# SketchyBar 2.24 crashes when it removes rows while it is moving the windows of the bar, e.g.
# because the name of the network changed (a window freed twice in window_defer_update).
# The rows are INSET from the edges, so the highlight doesn't touch them
row() {
  local name="network.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.connection)
  sets+=(--set "$name" padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above and below the rows and between the sections, as in apple.sh
space() {
  row "$1" drawing=on width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# text_row <name> <left> <left font> <left color> [<right> <right font> <right color>]: a row with
# a text on the left and, if given, one on the right, as in battery.sh. The rows that need less
# room add background.height
text_row() {
  local properties=(drawing=on width=$WIDTH icon.drawing=on icon="$2" icon.font="$3" icon.color=$4
                    icon.padding_left=$PADDING icon.padding_right=0 label.padding_left=0
                    icon.background.drawing=off
                    background.drawing=on background.color=$TRANSPARENT background.corner_radius=6
                    background.height=$ROW_HEIGHT)
  if [ -n "$5" ]; then
    # A fixed width includes the padding
    properties+=(icon.width=$((WIDTH - RIGHT_WIDTH - PADDING))
                 label.drawing=on label="$5" label.font="$6" label.color=$7 label.width=$((RIGHT_WIDTH + PADDING))
                 label.align=right label.padding_right=$PADDING)
  else
    properties+=(icon.width=dynamic label.drawing=off)
  fi
  row "$1" "${properties[@]}"
}

# button <name> <arguments>: right after the row, which lights up under the mouse; a click runs
# this with the arguments, already quoted
button() {
  sets+=(script="$0 $2")
  subscribes+=(--subscribe "network.row.$1" mouse.entered mouse.exited mouse.clicked)
}

# info_row <name> <title> <value> [<value color>]: a detail of the connection, hidden without a value
info_row() {
  text_row "$1" "$2" "$FONT" $TEXT "$3" "$FONT" "${4:-$SUBTEXT}"
  [ -n "$3" ] || sets+=(drawing=off)
}

# network_row <name> <level> <network> <right> <right font> <right color>: a Wi-Fi network, with the
# icon of its signal (helpers/network_icons.js) after the padding, then its name, both in the icon,
# and a text on the right. SketchyBar draws only an icon and a label in a row, and the icons of SF
# Symbols are text: so the icon is an image, which goes in the background of the icon, as in audio.sh
network_row() {
  local name="$3"
  [ ${#name} -gt 32 ] && name="${name:0:31}…"
  row "$1" drawing=on width=$WIDTH \
           icon.drawing=on icon="$name" icon.font="$FONT" icon.color=$TEXT icon.align=left \
           icon.padding_left=$((PADDING + ICON_WIDTH + ICON_GAP)) icon.padding_right=0 \
           icon.width=$((WIDTH - RIGHT_WIDTH - PADDING)) \
           icon.background.drawing=on icon.background.image="$NETWORK_ICONS/wifi_$2.png" \
           icon.background.image.scale=0.25 \
           icon.background.image.padding_left=$PADDING \
           label.drawing=on label="$4" label.font="$5" label.color=$6 label.width=$((RIGHT_WIDTH + PADDING)) \
           label.align=right label.padding_left=0 label.padding_right=$PADDING \
           background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT
}

# joining: the network the popup is joining, until wifi_networks_change says how it went or, if it
# never does, for two minutes
joining() {
  [ -f "$JOIN_FILE" ] && [ $(($(date +%s) - $(stat -f %m "$JOIN_FILE"))) -lt 120 ] && cat "$JOIN_FILE"
}

# networks_rows <known|other> <title> <rows> <networks>: the title and the networks of the list, up
# to <rows>, the one the Mac is on lit as in audio.sh. A click on another one joins it
networks_rows() {
  local i=0 name level security known right font color
  text_row "$1" "$2" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=20)
  [ -n "$4" ] || sets+=(drawing=off)
  while IFS=$'\t' read -r name level security known; do
    [ -n "$name" ] && [ $i -lt $3 ] || continue
    right="" font=$LOCK_FONT color=$SUBTEXT
    [ "$security" = open ] || right=$LOCK
    if [ "$name" = "$JOINING" ]; then
      right=$CONNECTING font=$FONT color=$YELLOW
    elif [ "$name" = "$FAILED_NETWORK" ]; then
      right=$FAILED font=$FONT color=$RED
    fi
    network_row "$1.$i" "$level" "$name" "$right" "$font" $color
    if [ "$name" = "$SSID" ]; then
      sets+=(background.color=$SURFACE script="$0 current")
    else
      sets+=(background.color=$TRANSPARENT)
      button "$1.$i" "join $(quote "$name")"
    fi
    i=$((i + 1))
  done <<< "$4"
  for ((; i < $3; i++)); do row "$1.$i" drawing=off; done
}

render_popup() {
  local permission networks known other
  names=() adds=() sets=() subscribes=()
  local items
  items="$(sketchybar --query connection | jq -r '.popup.items // [] | . - ["keep.connection"] | join(" ")')"
  { IFS= read -r permission; networks="$(cat)"; } 2>/dev/null < "$NETWORKS_FILE"
  [ "$WIFI_POWER" = on ] || networks=""
  # The network the Mac is on first, as in the macOS menu
  known="$({ awk -F'\t' -v ssid="$SSID" '$4 == 1 && $1 == ssid' <<< "$networks"; awk -F'\t' -v ssid="$SSID" '$4 == 1 && $1 != ssid' <<< "$networks"; } | head -$KNOWN)"
  other="$(awk -F'\t' '$4 != 1' <<< "$networks" | head -$OTHERS)"
  JOINING="$(joining)"

  local local_address router public="" public_color=$SUBTEXT public_connection vpn_address
  local_address="$(address "$PRIMARY_INTERFACE")"
  [ -n "$PRIMARY_INTERFACE" ] && router="$(router "$PRIMARY_INTERFACE")"
  [ -n "$VPN_INTERFACE" ] && vpn_address="$(address "$VPN_INTERFACE")"
  # The public address read last, dimmed when the connection changed since then
  if IFS=$'\t' read -r public public_connection 2>/dev/null < "$PUBLIC_FILE"; then
    [ -n "$public" ] || public=$UNAVAILABLE
    [ "$public_connection" = "$CONNECTION" ] || public_color=$OVERLAY
  fi

  local services=() states=() titles=() details=() enabled device service
  while IFS=$'\t' read -r enabled device service; do
    [ -n "$service" ] || continue
    services+=("$service") states+=("$enabled")
    # USB adapters are named after their speed, e.g. USB 10/100/1000 LAN: under Ethernet. A phone
    # shared over USB is named after itself
    case "$service" in
      *Ethernet* | *LAN*) titles+=("Ethernet") details+=("$service · ") ;;
      *) titles+=("$service") details+=("") ;;
    esac
    if [ "$enabled" = 0 ]; then
      details[${#details[@]} - 1]+=$DISABLED_TEXT
    elif grep -qx "$device" <<< "$CONNECTED"; then
      details[${#details[@]} - 1]+=$CONNECTED_TEXT
    else
      details[${#details[@]} - 1]+=$DISCONNECTED_TEXT
    fi
  done <<< "$(wired_services | head -$WIRED)"

  # The icons are as wide as each other: their width in px is in the PNG header, 4 px per point
  local a b c d
  read -r a b c d < <(od -An -tu1 -j16 -N4 "$NETWORK_ICONS/wifi_3.png" 2>/dev/null)
  ICON_WIDTH=$((((a << 24 | b << 16 | c << 8 | d) + 3) / 4))

  local widths network shown=()
  while IFS=$'\t' read -r network _; do
    [ -n "$network" ] || continue
    [ ${#network} -gt 32 ] && network="${network:0:31}…"
    shown+=("$network")
  done <<< "$known"$'\n'"$other"
  widths=($(text_widths HelveticaNeue-Bold 13 "$ADDRESS_TITLE" "$PUBLIC_TITLE" "$ROUTER_TITLE" "$VPN_TITLE" \
                          "$VPN_ADDRESS_TITLE" "${titles[@]}" "Wi-Fi" "$SETTINGS" \
                        -- HelveticaNeue-Bold 13 "${local_address:-$NONE}" "$public" "$UNAVAILABLE" "$router" \
                          "${VPN_NAME:-$VPN_OFF}" "$vpn_address" "$TURN_ON" "$TURN_OFF" "$CONNECTING" "$FAILED" \
                        -- HelveticaNeue-Bold 13 "${shown[@]}" \
                        -- HelveticaNeue-Medium 11 "${details[@]}" "$KNOWN_TITLE" "$OTHER_TITLE" "$SEARCHING" "$LOCATION"))
  RIGHT_WIDTH=${widths[1]:-0}
  WIDTH=$((PADDING + ${widths[0]:-0} + GAP + RIGHT_WIDTH + PADDING))
  local network_width=$((PADDING + ICON_WIDTH + ICON_GAP + ${widths[2]:-0} + GAP + RIGHT_WIDTH + PADDING))
  [ $network_width -gt $WIDTH ] && WIDTH=$network_width
  [ $((PADDING + ${widths[3]:-0} + PADDING)) -gt $WIDTH ] && WIDTH=$((PADDING + ${widths[3]:-0} + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))

  # The connection
  space top 4
  info_row address "$ADDRESS_TITLE" "${local_address:-$NONE}"
  info_row public "$PUBLIC_TITLE" "${public:-…}" $public_color
  info_row router "$ROUTER_TITLE" "$router"
  if [ -n "$VPN_NAME" ]; then
    info_row vpn "$VPN_TITLE" "$VPN_NAME" $GREEN
  else
    info_row vpn "$VPN_TITLE" "$VPN_OFF"
  fi
  info_row vpn.address "$VPN_ADDRESS_TITLE" "$vpn_address"

  # Ethernet: a row that turns each wired service off or on, as in System Settings (Disattiva
  # servizio), and what it is doing. The services come and go with their adapter
  local i
  for ((i = 0; i < ${#services[@]}; i++)); do
    space "ethernet.$i.gap" $SECTION_GAP
    if [ "${states[i]}" = 1 ]; then
      text_row "ethernet.$i" "${titles[i]}" "$FONT" $TEXT "$TURN_OFF" "$FONT" $PRIMARY
      button "ethernet.$i" "ethernet off $(quote "${services[i]}")"
    else
      text_row "ethernet.$i" "${titles[i]}" "$FONT" $TEXT "$TURN_ON" "$FONT" $PRIMARY
      button "ethernet.$i" "ethernet on $(quote "${services[i]}")"
    fi
    text_row "ethernet.$i.details" "${details[i]}" "$SMALL_FONT" $SUBTEXT
    sets+=(background.height=16)
  done
  for ((; i < WIRED; i++)); do
    row "ethernet.$i.gap" drawing=off
    row "ethernet.$i" drawing=off
    row "ethernet.$i.details" drawing=off
  done

  # Wi-Fi: the row that turns it off or on, then the networks, or why there are none
  if [ -n "$WIFI_DEVICE" ]; then
    space wifi.gap $SECTION_GAP
    if [ "$WIFI_POWER" = on ]; then
      text_row wifi "Wi-Fi" "$FONT" $TEXT "$TURN_OFF" "$FONT" $PRIMARY
      button wifi "wifi off"
    else
      text_row wifi "Wi-Fi" "$FONT" $TEXT "$TURN_ON" "$FONT" $PRIMARY
      button wifi "wifi on"
    fi
    text_row location "$LOCATION" "$SMALL_FONT" $PRIMARY
    button location location
    [ "$WIFI_POWER" = on ] && [ "$permission" = denied ] || sets+=(drawing=off)
    text_row searching "$SEARCHING" "$SMALL_FONT" $SUBTEXT
    sets+=(background.height=20)
    [ "$WIFI_POWER" = on ] && [ "$permission" != denied ] && [ -z "$networks" ] || sets+=(drawing=off)
    networks_rows known "$KNOWN_TITLE" $KNOWN "$known"
    networks_rows other "$OTHER_TITLE" $OTHERS "$other"
  fi

  space settings.gap $SECTION_GAP
  text_row settings "$SETTINGS" "$FONT" $PRIMARY
  button settings settings
  space bottom 4

  if [ "$items" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" "${subscribes[@]}"
  else
    sketchybar --remove '/network\.row\..*/' "${adds[@]}" "${sets[@]}" "${subscribes[@]}"
  fi
}

# The public address, from a service that answers with the address it sees: through the VPN, its
# own. In the background, then the popup again
public_address() {
  local address
  address="$(curl -s --max-time 5 https://api.ipify.org)"
  [[ "$address" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || address=""
  printf '%s\t%s\n' "$address" "$CONNECTION" > "$PUBLIC_FILE"
  render_popup
}

update() {
  read_network
  update_bar
  render_popup
}

# A popup row: Wi-Fi or an Ethernet service off or on, a network to join, the Location Services
# settings or the Network ones, or the network the Mac is on
case "$1" in
  current) exit 0 ;;
  wifi | ethernet | join | location | settings)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
      mouse.clicked)
        case "$1" in
          wifi)
            read_network
            networksetup -setairportpower "$WIFI_DEVICE" "$2"
            update
            ;;
          ethernet)
            networksetup -setnetworkserviceenabled "$3" "$2"
            update
            ;;
          # One network at a time: the clicks meanwhile are ignored
          join)
            [ -n "$(joining)" ] && exit 0
            printf '%s' "$2" > "$JOIN_FILE"
            sketchybar --set "$NAME" label="$CONNECTING" label.font="$FONT" label.color=$YELLOW
            "$HELPER" join "$2"
            ;;
          location)
            sketchybar --set connection popup.drawing=off
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            ;;
          settings)
            sketchybar --set connection popup.drawing=off
            open "x-apple.systempreferences:com.apple.Network-Settings.extension"
            ;;
        esac
        ;;
    esac
    exit 0
    ;;
esac

# The popup is kept up to date also while closed, so that it opens at once; the click looks for
# networks again and reads the public address
case "$SENDER" in
  mouse.clicked)
    if [ "$(sketchybar --query connection | jq -r .popup.drawing)" = on ]; then
      sketchybar --set connection popup.drawing=off
    else
      sketchybar --set connection popup.drawing=on
      "$HELPER" scan 2>/dev/null
      read_network
      render_popup
      public_address &
    fi
    ;;
  mouse.exited.global) sketchybar --set connection popup.drawing=off ;;
  # From helpers/wifi_networks.app: the networks, and how the one the popup asked for went. A network
  # of a company or a university is joined in System Settings, which asks for the user name too
  wifi_networks_change)
    printf '%s\n%s\n' "$PERMISSION" "$NETWORKS" > "$NETWORKS_FILE"
    if [ -n "$JOINED" ]; then
      rm -f "$JOIN_FILE"
      case "$RESULT" in
        failed | missing | denied) FAILED_NETWORK="$JOINED" ;;
        enterprise)
          sketchybar --set connection popup.drawing=off
          open "x-apple.systempreferences:com.apple.wifi-settings-extension"
          ;;
      esac
    fi
    update
    ;;
  # wifi_change, system_woke, the update_freq and the first run. The other items only open the popup
  *) [ "$NAME" = network ] && update ;;
esac
