#!/usr/bin/env bash

# Default audio output and input: updates audio_output and audio_input, each followed by the
# battery of the device (audio_output_battery, audio_input_battery) when it has one, or only the
# output when they are the same device or the Mac's own speakers and microphone.
# helpers/audio_devices reports their id, transport, type, name and battery (Bluetooth only);
# the icons are SF Symbols, except for those SF Symbols doesn't have, images that sketchybarrc
# makes: the Galaxy Buds out of a photo (helpers/galaxy_buds_icon.js), and the Mac, a display or
# audio glasses with a speaker badge, a microphone badge or both (helpers/audio_icons.js)
# A click on any of the four items opens the popup of audio_output: for the output and then the
# input, the volume of the default device with a slider, or a note when macOS can't change it
# (e.g. the Arctis Nova Pro Wireless, whose volume is on its base station), and the devices with
# the battery of the Bluetooth ones, where a click makes one the default; then the paired Bluetooth
# audio devices, where a click connects or disconnects one (helpers/bluetooth_devices.app).
# The audio items run this with no arguments, the sliders with volume <output|input>, the devices
# with select <output|input> <uid>, or with current for the default ones, and the Bluetooth ones
# with bluetooth <connect|disconnect> <address>

SPEAKER=􀊦           # speaker.wave.2
EXTERNAL_SPEAKER=􀝎  # hifispeaker
HEADPHONES=􀑈        # headphones
HEADSET=􂣵           # headset
AIRPODS=􀟥           # airpods
AIRPODS_PRO=􂭃       # airpods.pro
AIRPODS_MAX=􀺹       # airpods.max
GLASSES=􀖆           # eyeglasses
MONITOR=􀢹           # display
AIRPLAY=􀑢           # airplayaudio
VIRTUAL=􀙫           # waveform
MIC=􀊰               # mic
EXTERNAL_MIC=􀑫      # music.mic
BATTERY_100=􀛨       # battery.100
BATTERY_75=􀺸        # battery.75
BATTERY_50=􀺶        # battery.50
BATTERY_25=􀛩        # battery.25
BATTERY_0=􀛪         # battery.0
GALAXY_BUDS_ICON="$CONFIG_DIR/helpers/galaxy_buds_icon.png"
AUDIO_ICONS="$CONFIG_DIR/helpers/audio_icons"
HELPER="$CONFIG_DIR/helpers/audio_devices"

source "$CONFIG_DIR/colors.sh"

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
BATTERY_FONT="SF Pro:Semibold:11.0"
MIN_WIDTH=260
INSET=4            # between the rows and the edge of the popup, as in apple.sh
PADDING=8          # inside the rows
GAP=8              # between the icon and the name of a device
COLUMN_GAP=16      # between the name of a device and the text on its right
ICON_WIDTH=31      # the column of the device icons, as wide as the widest, the glasses
ROW_HEIGHT=26      # of a device
NAME_LENGTH=14     # characters of the names in the bar, with the … (the popup has them whole)
SLIDER_HEIGHT=8
OUTPUT_TITLE="Uscita"
INPUT_TITLE="Ingresso"
BLUETOOTH_TITLE="Bluetooth"
FIXED_VOLUME="Volume regolabile solo dal dispositivo"
CONNECT="Connetti"
DISCONNECT="Disconnetti"
CONNECTING="Connessione…"
DISCONNECTING="Disconnessione…"
FAILED="Non riuscito"
DENIED="Non consentito"
BLUETOOTH_APP="$CONFIG_DIR/helpers/bluetooth_devices.app"
BLUETOOTH_LOCK="${TMPDIR:-/tmp}/sketchybar_bluetooth"
KNOB=􀀁  # circle.fill

# image_or <png> <symbol>: the image, or the SF Symbol when sketchybarrc couldn't make it
image_or() {
  if [ -f "$1" ]; then echo "$1"; else echo "$2"; fi
}

# icon_for <output|input> <transport> <type> <name>: an SF Symbol, or the path of an image
icon_for() {
  case "$1:$4" in
    # "Galaxy Buds4 Pro (XXXX)" unless renamed
    *Buds4\ Pro*) image_or "$GALAXY_BUDS_ICON" "$HEADPHONES" ;;
    *AirPods\ Max*) echo "$AIRPODS_MAX" ;;
    *AirPods\ Pro*) echo "$AIRPODS_PRO" ;;
    *AirPods*) echo "$AIRPODS" ;;
    # Audio glasses: the frames for the sound, while the input keeps the headset icon
    output:*[Gg]lasses*) echo "$GLASSES" ;;
    *)
      case "$1:$2:$3" in
        *:virtual:*) echo "$VIRTUAL" ;;
        output:*:headphones | output:*:headset) echo "$HEADPHONES" ;;
        # Bluetooth devices that don't say they are speakers are nearly always headphones
        output:bluetooth:speaker) echo "$EXTERNAL_SPEAKER" ;;
        output:bluetooth:*) echo "$HEADPHONES" ;;
        output:builtin:*) echo "$SPEAKER" ;;
        output:display:*) echo "$MONITOR" ;;
        output:airplay:*) echo "$AIRPLAY" ;;
        output:*) echo "$EXTERNAL_SPEAKER" ;;
        input:*:headset | input:bluetooth:*) echo "$HEADSET" ;;
        input:builtin:*) echo "$MIC" ;;
        input:*) echo "$EXTERNAL_MIC" ;;
      esac
      ;;
  esac
}

# badged <transport> <type> <name>: which of the images with a speaker or microphone badge is the
# device's, for those whose symbol would be the same for both: the Mac (a laptop for a MacBook, not
# the headphone jack), a display, audio glasses
badged() {
  case "$1:$2:$3" in
    builtin:headphones:* | builtin:headset:*) ;;
    builtin:*:*MacBook*) echo laptop ;;
    builtin:*) echo desktop ;;
    display:*) echo display ;;
    *[Gg]lasses*) echo glasses ;;
  esac
}

# icon <output|input> <speaker|microphone|speaker_microphone> <transport> <type> <name>: the image
# of the device with those badges, or else the icon of icon_for
icon() {
  local device
  device=$(badged "$3" "$4" "$5")
  if [ -n "$device" ] && [ -f "$AUDIO_ICONS/${device}_$2.png" ]; then
    echo "$AUDIO_ICONS/${device}_$2.png"
  else
    icon_for "$1" "$3" "$4" "$5"
  fi
}

# icon_settings <icon>: sets ICON to the icon settings of an audio item, for an SF Symbol or an
# image. The images are drawn at 4 px per point, hence the scale. An image ignores the padding of
# the icon and starts at its left edge: image.padding_left leaves the same space as before the
# symbols (icon.padding_left plus their origin), in an icon as wide as that and the image, whose
# width in px is in the PNG header. icon.width=dynamic undoes it
icon_settings() {
  case "$1" in
    /*)
      local a b c d
      read -r a b c d < <(od -An -tu1 -j16 -N4 "$1")
      ICON=(icon="" icon.width=$((8 + ((a << 24 | b << 16 | c << 8 | d) + 3) / 4)) icon.background.drawing=on
            icon.background.image="$1" icon.background.image.scale=0.25
            icon.background.image.padding_left=8)
      ;;
    *) ICON=(icon="$1" icon.width=dynamic icon.background.drawing=off) ;;
  esac
}

# battery_level <percentage>: sets LEVEL to the icon of the closest level and LEVEL_COLOR, red at
# 20% or less as in the macOS battery menu
battery_level() {
  LEVEL=$BATTERY_0 LEVEL_COLOR=$SUBTEXT
  if [ "$1" -ge 88 ]; then LEVEL=$BATTERY_100
  elif [ "$1" -ge 63 ]; then LEVEL=$BATTERY_75
  elif [ "$1" -ge 38 ]; then LEVEL=$BATTERY_50
  elif [ "$1" -ge 13 ]; then LEVEL=$BATTERY_25
  fi
  [ "$1" -le 20 ] && LEVEL_COLOR=$RED
}

# battery_for <percentage>: the settings of a battery item, hidden when the device has none
battery_for() {
  [ -n "$1" ] || { echo drawing=off; return; }
  battery_level "$1"
  echo drawing=on icon="$LEVEL" icon.color=$LEVEL_COLOR label="$1%"
}

# common_name <name> <name>: the words the two names share at the end, or else at the start
common_name() {
  local a b i=0
  read -ra a <<< "$1"
  read -ra b <<< "$2"
  while [ $i -lt ${#a[@]} ] && [ $i -lt ${#b[@]} ] && [ "${a[${#a[@]}-1-i]}" = "${b[${#b[@]}-1-i]}" ]; do
    i=$((i + 1))
  done
  if [ $i -gt 0 ]; then
    echo "${a[*]:${#a[@]}-i}"
    return
  fi
  while [ $i -lt ${#a[@]} ] && [ $i -lt ${#b[@]} ] && [ "${a[i]}" = "${b[i]}" ]; do
    i=$((i + 1))
  done
  echo "${a[*]:0:i}"
}

# short_name <name>: the name, or if it is longer than NAME_LENGTH the words that fit with …, e.g.
# AirPods Pro… for AirPods Pro di Luca, or the start of a first word too long
short_name() {
  if [ ${#1} -le $NAME_LENGTH ]; then
    echo "$1"
    return
  fi
  local words word short="" longer
  read -ra words <<< "$1"
  for word in "${words[@]}"; do
    longer="${short:+$short }$word"
    [ ${#longer} -lt $NAME_LENGTH ] || break
    short=$longer
  done
  echo "${short:-${1:0:NAME_LENGTH-1}}…"
}

# The bar items: the default output and input, and their battery
update_bar() {
  IFS=$'\t' read -r OUT_ID OUT_TRANSPORT OUT_TYPE OUT_NAME OUT_BATTERY < <("$HELPER" output)
  IFS=$'\t' read -r IN_ID IN_TRANSPORT IN_TYPE IN_NAME IN_BATTERY < <("$HELPER" input)

  # Same device for both (e.g. Bluetooth headphones): only the output, whose icon is the device
  # itself, while the input one would be a headset or a microphone; with both badges if it has them
  OUT_BADGES=speaker
  [ "$OUT_ID" = "$IN_ID" ] && IN_ID="" OUT_BADGES=speaker_microphone

  # The Mac's own speakers and microphone, two devices: only the output too, as the Mac with both
  # badges, named with what "Altoparlanti MacBook Pro" and "Microfono MacBook Pro" (or "MacBook Pro
  # Speakers" and "MacBook Pro Microphone") share. Headphones in the jack share nothing with the
  # microphone
  if [ "$OUT_TRANSPORT:$IN_TRANSPORT" = builtin:builtin ]; then
    MAC="$(common_name "$OUT_NAME" "$IN_NAME")"
    [ -n "$MAC" ] && OUT_NAME=$MAC IN_ID="" OUT_BADGES=speaker_microphone
  fi

  output=(drawing=off)
  if [ -n "$OUT_ID" ]; then
    icon_settings "$(icon output $OUT_BADGES "$OUT_TRANSPORT" "$OUT_TYPE" "$OUT_NAME")"
    output=(drawing=on "${ICON[@]}" label="$(short_name "$OUT_NAME")")
  fi

  input=(drawing=off)
  if [ -n "$IN_ID" ]; then
    icon_settings "$(icon input microphone "$IN_TRANSPORT" "$IN_TYPE" "$IN_NAME")"
    input=(drawing=on "${ICON[@]}" label="$(short_name "$IN_NAME")")
  fi

  [ -n "$OUT_ID" ] || OUT_BATTERY=""
  [ -n "$IN_ID" ] || IN_BATTERY=""
  read -ra output_battery <<< "$(battery_for "$OUT_BATTERY")"
  read -ra input_battery <<< "$(battery_for "$IN_BATTERY")"

  sketchybar --set audio_output "${output[@]}" --set audio_output_battery "${output_battery[@]}" \
             --set audio_input "${input[@]}" --set audio_input_battery "${input_battery[@]}"
}

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Medium 11 <text>... prints two widths. SketchyBar measures text only once it
# draws it, but the rows need a fixed width to line up the percentages and to highlight a whole row
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

# Each render lists all the popup rows, as in claude.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are INSET from the edges, so the highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="audio.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.audio_output)
  sets+=(--set "$name" padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room below the last row, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# title_row <output|input> <title> <height>: the title, with the percentage of the volume on the
# right. The title of the input is taller, which parts it from the output devices
title_row() {
  row "$1.title" width=$WIDTH icon.drawing=on icon="$2" icon.font="$FONT" icon.color=$TEXT \
                 icon.padding_left=$PADDING icon.padding_right=0 icon.width=$((WIDTH - PERCENT_WIDTH - PADDING)) \
                 label.font="$FONT" label.color=$SUBTEXT label.width=$((PERCENT_WIDTH + PADDING)) \
                 label.align=right label.padding_left=0 label.padding_right=$PADDING \
                 background.drawing=on background.color=$TRANSPARENT background.height=$3
}

# volume_rows <output|input>: the slider, which sets the volume when released, and the note that
# takes its place when macOS can't change the volume; volume_sets shows one of them
volume_rows() {
  local name="audio.$1.volume" width=$((WIDTH - 2 * PADDING))
  names+=("$name")
  adds+=(--add slider "$name" popup.audio_output $width)
  sets+=(--set "$name" padding_left=$((INSET + PADDING)) padding_right=$((INSET + PADDING))
                       icon.drawing=off label.drawing=off
                       slider.width=$width slider.highlight_color=$PRIMARY
                       slider.background.height=$SLIDER_HEIGHT slider.background.color=$SURFACE
                       slider.background.corner_radius=$((SLIDER_HEIGHT / 2))
                       slider.knob="$KNOB" slider.knob.font="SF Pro:Regular:16.0" slider.knob.color=$TEXT
                       background.drawing=on background.color=$TRANSPARENT background.height=24
                       script="$0 volume $1"
         --subscribe "$name" mouse.clicked)
  row "$1.fixed" width=$WIDTH icon.drawing=on icon="$FIXED_VOLUME" icon.font="$SMALL_FONT" \
                 icon.color=$SUBTEXT icon.padding_left=$PADDING icon.padding_right=0 label.drawing=off \
                 background.drawing=on background.color=$TRANSPARENT background.height=24
}

# volume_sets <output|input>: the percentage and the slider at the volume of the default device,
# or the note in place of the slider; without a default device, e.g. no microphone at all, nothing
# but the devices
volume_sets() {
  local volume
  if ! volume="$("$HELPER" volume "$1")"; then
    sets+=(--set "audio.$1.title" drawing=off --set "audio.$1.volume" drawing=off --set "audio.$1.fixed" drawing=off)
  elif [ -n "$volume" ]; then
    sets+=(--set "audio.$1.title" drawing=on label="$volume%"
           --set "audio.$1.volume" drawing=on slider.percentage="$volume"
           --set "audio.$1.fixed" drawing=off)
  else
    sets+=(--set "audio.$1.title" drawing=on label=""
           --set "audio.$1.volume" drawing=off
           --set "audio.$1.fixed" drawing=on)
  fi
}

# image <icon>: an icon of the icon function as an image: the same when it is one already, or else
# the one helpers/audio_icons.js draws of the SF Symbol, named after it
image() {
  local name
  case "$1" in
    /*) echo "$1"; return ;;
    "$SPEAKER") name=speaker.wave.2 ;;
    "$EXTERNAL_SPEAKER") name=hifispeaker ;;
    "$HEADPHONES") name=headphones ;;
    "$HEADSET") name=headset ;;
    "$AIRPODS") name=airpods ;;
    "$AIRPODS_PRO") name=airpods.pro ;;
    "$AIRPODS_MAX") name=airpods.max ;;
    "$GLASSES") name=eyeglasses ;;
    "$MONITOR") name=display ;;
    "$AIRPLAY") name=airplayaudio ;;
    "$VIRTUAL") name=waveform ;;
    "$MIC") name=mic ;;
    "$EXTERNAL_MIC") name=music.mic ;;
  esac
  echo "$AUDIO_ICONS/$name.png"
}

# device_settings <image> <name> <right text> <right font> <right color>: sets DEVICE to the
# settings of a row with a device: its image, centered in a column ICON_WIDTH wide after the
# padding (its width in px is in the PNG header, 4 px per point), then its name, both in the icon,
# and a text on the right, the label. SketchyBar draws only an icon and a label in a row, and the
# icons of SF Symbols are text: so all of them are images, which go in the background of the icon
device_settings() {
  local a b c d
  read -r a b c d < <(od -An -tu1 -j16 -N4 "$1")
  DEVICE=(drawing=on width=$WIDTH
          icon.drawing=on icon="$2" icon.font="$FONT" icon.color=$TEXT icon.align=left
          icon.padding_left=$((PADDING + ICON_WIDTH + GAP)) icon.padding_right=0
          icon.width=$((WIDTH - RIGHT_WIDTH - PADDING))
          icon.background.drawing=on icon.background.image="$1" icon.background.image.scale=0.25
          icon.background.image.padding_left=$((PADDING + (ICON_WIDTH - ((a << 24 | b << 16 | c << 8 | d) + 3) / 4) / 2))
          label.drawing=on label="$3" label.font="$4" label.color=$5 label.width=$((RIGHT_WIDTH + PADDING))
          label.align=right label.padding_left=0 label.padding_right=$PADDING
          background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT)
}

# quote <text>: the text in single quotes, for the shell that runs a script. Not printf %q, whose
# backslashes --query leaves unescaped in its JSON
quote() {
  local quote="'\\''"
  echo "'${1//\'/$quote}'"
}

# device_row <output|input> <index> <uid> <default> <transport> <type> <name> <battery>: the
# device with its battery, if it has one, on a background when it is the default, else lit up
# under the mouse
device_row() {
  local badge=speaker state
  [ "$1" = input ] && badge=microphone
  if [ "$4" = 1 ]; then
    state=(background.color=$SURFACE script="$0 current")
  else
    state=(background.color=$TRANSPARENT script="$0 select $1 $(quote "$3")")
  fi
  LEVEL="" LEVEL_COLOR=$SUBTEXT
  [ -n "$8" ] && battery_level "$8"
  device_settings "$(image "$(icon "$1" $badge "$5" "$6" "$7")")" "$7" "${8:+$LEVEL $8%}" "$BATTERY_FONT" $LEVEL_COLOR
  row "$1.device.$2" "${DEVICE[@]}" "${state[@]}"
  sets+=(--subscribe "audio.$1.device.$2" mouse.entered mouse.exited mouse.clicked)
}

# busy <address>: the Bluetooth action in progress on the device, if any. Its lock holds the pid of
# the background job that runs it
busy() {
  local action lock
  for action in connect disconnect; do
    lock="$BLUETOOTH_LOCK.$1.$action"
    [ -f "$lock" ] && kill -0 "$(cat "$lock")" 2>/dev/null && echo $action && return
  done
  return 1
}

# bluetooth_row <index> <address> <connected> <type> <name>: a paired Bluetooth audio device, with
# on the right what a click does, or what it is doing
bluetooth_row() {
  local action=connect text=$CONNECT color=$PRIMARY
  [ "$3" = 1 ] && action=disconnect text=$DISCONNECT
  case "$(busy "$2")" in
    connect) text=$CONNECTING color=$YELLOW ;;
    disconnect) text=$DISCONNECTING color=$YELLOW ;;
  esac
  device_settings "$(image "$(icon output speaker bluetooth "$4" "$5")")" "$5" "$text" "$FONT" $color
  row "bluetooth.device.$1" "${DEVICE[@]}" background.color=$TRANSPARENT script="$0 bluetooth $action $2"
  sets+=(--subscribe "audio.bluetooth.device.$1" mouse.entered mouse.exited mouse.clicked)
}

# pool <section> <devices>: how many device rows the section has, those left over hidden. While
# the popup is open never fewer than it has already: SketchyBar can only add a row at the bottom,
# so a new row in the middle means removing and adding again those after it, and removing the row
# under the mouse closes the popup (mouse.exited.global)
pool() {
  local rows=0 item
  if [ "$OPEN" = on ]; then
    for item in $ITEMS; do
      case "$item" in "audio.$1.device."*) rows=$((rows + 1)) ;; esac
    done
  fi
  echo $(($2 > rows ? $2 : rows))
}

# section <output|input> <title> <title height> <rows> <devices, as listed by the helper>: the
# title, the volume and the devices
section() {
  [ "$4" -gt 0 ] || return
  title_row "$1" "$2" "$3"
  volume_rows "$1"
  volume_sets "$1"
  local i=0 uid default transport type name battery
  while IFS=$'\t' read -r uid default transport type name battery; do
    [ -n "$uid" ] || continue
    device_row "$1" $i "$uid" "$default" "$transport" "$type" "$name" "$battery"
    i=$((i + 1))
  done <<< "$5"
  for ((; i < $4; i++)); do row "$1.device.$i" drawing=off; done
}

# bluetooth_section <rows> <devices, as listed by the helper>: the title and the devices
bluetooth_section() {
  [ "$1" -gt 0 ] || return
  local i=0 address connected type name
  title_row bluetooth "$BLUETOOTH_TITLE" 38
  sets+=(--set audio.bluetooth.title drawing=$([ -n "$2" ] && echo on || echo off) label="")
  while IFS=$'\t' read -r address connected type name; do
    [ -n "$address" ] || continue
    bluetooth_row $i "$address" "$connected" "$type" "$name"
    i=$((i + 1))
  done <<< "$2"
  for ((; i < $1; i++)); do row "bluetooth.device.$i" drawing=off; done
}

# render_popup: sets the popup rows, and removes and adds them only when they aren't the ones
# already there. The device rows are a pool for each section (pool): a Bluetooth device that
# connects or disconnects only shows or hides a row, since the output and input have a row in
# reserve for each one that isn't connected
render_popup() {
  local devices outputs inputs bluetooth device_names=() actions=() battery=() name connected value widths
  read -r OPEN ITEMS <<< "$(sketchybar --query audio_output | jq -r '"\(.popup.drawing) \(.popup.items // [] | join(" "))"')"
  devices="$("$HELPER" list)"
  outputs="$(grep $'^output\t' <<< "$devices" | cut -f2-)"
  inputs="$(grep $'^input\t' <<< "$devices" | cut -f2-)"
  bluetooth="$(grep $'^bluetooth\t' <<< "$devices" | cut -f2-)"

  local disconnected=0
  while IFS=$'\t' read -r _ _ _ _ name value; do
    [ -n "$name" ] && device_names+=("$name")
    [ -n "$value" ] && battery=("$BATTERY_100 100%")
  done <<< "$outputs"$'\n'"$inputs"
  while IFS=$'\t' read -r _ connected _ name; do
    [ -n "$name" ] || continue
    device_names+=("$name")
    [ "$connected" = 1 ] || disconnected=$((disconnected + 1))
  done <<< "$bluetooth"
  [ -n "$bluetooth" ] && actions=("$CONNECT" "$DISCONNECT" "$CONNECTING" "$DISCONNECTING" "$FAILED" "$DENIED")

  # The percentage, the names after the icon, the title or the note, and the text on the right of
  # the devices, whichever is the widest
  widths=($(text_widths HelveticaNeue-Bold 13 "100%" -- HelveticaNeue-Bold 13 "${device_names[@]}" \
                        -- HelveticaNeue-Bold 13 "$OUTPUT_TITLE" "$INPUT_TITLE" "$BLUETOOTH_TITLE" \
                        -- HelveticaNeue-Medium 11 "$FIXED_VOLUME" -- HelveticaNeue-Bold 13 "${actions[@]}" \
                        -- SFPro-Semibold 11 "${battery[@]}"))
  PERCENT_WIDTH=${widths[0]:-0}
  RIGHT_WIDTH=$((${widths[4]:-0} > ${widths[5]:-0} ? ${widths[4]:-0} : ${widths[5]:-0}))
  local right=0
  [ $RIGHT_WIDTH -gt 0 ] && right=$((COLUMN_GAP + RIGHT_WIDTH))
  WIDTH=$((PADDING + ICON_WIDTH + GAP + ${widths[1]:-0} + right + PADDING))
  [ $((PADDING + ${widths[2]:-0} + GAP + PERCENT_WIDTH + PADDING)) -gt $WIDTH ] &&
    WIDTH=$((PADDING + ${widths[2]:-0} + GAP + PERCENT_WIDTH + PADDING))
  [ $((PADDING + ${widths[3]:-0} + PADDING)) -gt $WIDTH ] && WIDTH=$((PADDING + ${widths[3]:-0} + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))

  section output "$OUTPUT_TITLE" 30 "$(pool output $(($(grep -c . <<< "$outputs") + disconnected)))" "$outputs"
  section input "$INPUT_TITLE" 38 "$(pool input $(($(grep -c . <<< "$inputs") + disconnected)))" "$inputs"
  bluetooth_section "$(pool bluetooth "$(grep -c . <<< "$bluetooth")")" "$bluetooth"
  space bottom 4
  if [ "$ITEMS" = "${names[*]}" ]; then
    sketchybar "${sets[@]}"
  else
    sketchybar --remove '/audio\..*/' "${adds[@]}" "${sets[@]}"
  fi
}

# bluetooth <connect|disconnect> <address>: helpers/bluetooth_devices.app connects or disconnects
# the device, since macOS lets only an app that asked for it use Bluetooth. Meanwhile the row says
# so and ignores the clicks, and if it fails it says why until the popup is set again. When it
# connects, its audio comes a moment later, and with it audio_device_change
bluetooth() {
  busy "$2" > /dev/null && return
  local lock="$BLUETOOTH_LOCK.$2.$1" result status text=$CONNECTING
  shlock -f "$lock" -p "$(exec sh -c 'echo $PPID')" || return
  [ "$1" = disconnect ] && text=$DISCONNECTING
  sketchybar --set "$NAME" label="$text" label.color=$YELLOW
  result="$(mktemp)"
  # open -W can't wait for an app that is already gone when it looks for it: wait for its answer,
  # which may take the minute of the Bluetooth permission prompt, then a few seconds to connect
  # and up to 10 for the device to follow
  open -g -n -o "$result" "$BLUETOOTH_APP" --args "$1" "$2"
  local i
  for ((i = 0; i < 450; i++)); do
    [ -s "$result" ] && break
    sleep 0.2
  done
  status="$(cat "$result")"
  rm -f "$result"
  # The row says the device is connected when its audio is (audio_devices list), which comes a
  # moment after the device: until then, for up to 10 seconds, it stays busy
  if [ "$status" = ok ]; then
    local connected=1
    [ "$1" = disconnect ] && connected=0
    for ((i = 0; i < 50; i++)); do
      [ "$("$HELPER" list | awk -F'\t' -v address="$2" '$1 == "bluetooth" && $2 == address {print $3}')" = $connected ] &&
        break
      sleep 0.2
    done
  fi
  rm -f "$lock"
  case "$status" in
    ok) render_popup ;;
    denied) sketchybar --set "$NAME" label="$DENIED" label.color=$RED ;;
    *) sketchybar --set "$NAME" label="$FAILED" label.color=$RED ;;
  esac
}

# A popup row: a slider, which gives the percentage where it was released, a device or a Bluetooth
# device. SketchyBar kills its scripts after 60 seconds, and connecting can take a while, so
# Bluetooth runs in the background
case "$1" in
  volume)
    [ "$SENDER" = mouse.clicked ] && "$HELPER" volume "$2" "$PERCENTAGE" &&
      sketchybar --set "audio.$2.title" label="$PERCENTAGE%"
    exit 0
    ;;
  select | bluetooth)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
      mouse.clicked)
        if [ "$1" = select ]; then
          "$HELPER" set "$2" "$3" && render_popup
        else
          bluetooth "$2" "$3" &
        fi
        ;;
    esac
    exit 0
    ;;
  current) exit 0 ;;
esac

# The popup is kept up to date also while closed, so that it opens at once; the click reads the
# batteries and the Bluetooth devices again
case "$SENDER" in
  mouse.clicked)
    if [ "$(sketchybar --query audio_output | jq -r .popup.drawing)" = on ]; then
      sketchybar --set audio_output popup.drawing=off
    else
      sketchybar --set audio_output popup.drawing=on
      render_popup
    fi
    ;;
  mouse.exited.global) sketchybar --set audio_output popup.drawing=off ;;
  # From helpers/audio_devices, also for the volume keys
  audio_volume_change)
    volume_sets output
    volume_sets input
    sketchybar "${sets[@]}"
    ;;
  *)
    # The other items only open the popup
    [ "$NAME" = audio_output ] || exit 0
    render_popup
    update_bar
    ;;
esac
