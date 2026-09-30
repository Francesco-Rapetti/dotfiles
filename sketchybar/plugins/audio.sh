#!/usr/bin/env bash

# Default audio output and input: updates audio_output and audio_input, each followed by the
# battery of the device (audio_output_battery, audio_input_battery) when it has one, or only the
# output when they are the same device.
# helpers/audio_devices reports their id, transport, type, name and battery (Bluetooth only);
# the icons are SF Symbols, except for the Galaxy Buds, which SF Symbols doesn't have: an image
# that sketchybarrc makes out of a photo with helpers/galaxy_buds_icon.js

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

SUBTEXT=0xffa6adc8
RED=0xfff38ba8

# icon_for <output|input> <transport> <type> <name>: an SF Symbol, or galaxy_buds for the image
icon_for() {
  case "$1:$4" in
    # "Galaxy Buds4 Pro (XXXX)" unless renamed; without the image they are just headphones
    *Buds4\ Pro*) [ -f "$GALAXY_BUDS_ICON" ] && echo galaxy_buds || echo "$HEADPHONES" ;;
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

# icon_settings <icon>: sets ICON to the icon settings of an audio item, for an SF Symbol or the
# image. The photo cropped to 375 × 291 px, at 0.045: about as big as the AirPods symbols. The
# image ignores the padding of the icon and starts at its left edge: image.padding_left leaves the
# same space as before the symbols (icon.padding_left plus their origin), in an icon as wide as
# that and the image. icon.width=dynamic undoes it
icon_settings() {
  if [ "$1" = galaxy_buds ]; then
    ICON=(icon="" icon.width=25 icon.background.drawing=on icon.background.image="$GALAXY_BUDS_ICON"
          icon.background.image.scale=0.045 icon.background.image.padding_left=8)
  else
    ICON=(icon="$1" icon.width=dynamic icon.background.drawing=off)
  fi
}

# battery_for <percentage>: the settings of a battery item, hidden when the device has none.
# The icon is the closest level, red at 20% or less as in the macOS battery menu
battery_for() {
  [ -n "$1" ] || { echo drawing=off; return; }
  local icon=$BATTERY_0 color=$SUBTEXT
  if [ "$1" -ge 88 ]; then icon=$BATTERY_100
  elif [ "$1" -ge 63 ]; then icon=$BATTERY_75
  elif [ "$1" -ge 38 ]; then icon=$BATTERY_50
  elif [ "$1" -ge 13 ]; then icon=$BATTERY_25
  fi
  [ "$1" -le 20 ] && color=$RED
  echo drawing=on icon="$icon" icon.color=$color label="$1%"
}

IFS=$'\t' read -r OUT_ID OUT_TRANSPORT OUT_TYPE OUT_NAME OUT_BATTERY < <("$CONFIG_DIR/helpers/audio_devices" output)
IFS=$'\t' read -r IN_ID IN_TRANSPORT IN_TYPE IN_NAME IN_BATTERY < <("$CONFIG_DIR/helpers/audio_devices" input)

# Same device for both (e.g. Bluetooth headphones): only the output, whose icon is the device
# itself, while the input one would be a headset or a microphone
[ "$OUT_ID" = "$IN_ID" ] && IN_ID=""

output=(drawing=off)
if [ -n "$OUT_ID" ]; then
  icon_settings "$(icon_for output "$OUT_TRANSPORT" "$OUT_TYPE" "$OUT_NAME")"
  output=(drawing=on "${ICON[@]}" label="$OUT_NAME")
fi

input=(drawing=off)
if [ -n "$IN_ID" ]; then
  icon_settings "$(icon_for input "$IN_TRANSPORT" "$IN_TYPE" "$IN_NAME")"
  input=(drawing=on "${ICON[@]}" label="$IN_NAME")
fi

[ -n "$OUT_ID" ] || OUT_BATTERY=""
[ -n "$IN_ID" ] || IN_BATTERY=""
read -ra output_battery <<< "$(battery_for "$OUT_BATTERY")"
read -ra input_battery <<< "$(battery_for "$IN_BATTERY")"

sketchybar --set audio_output "${output[@]}" --set audio_output_battery "${output_battery[@]}" \
           --set audio_input "${input[@]}" --set audio_input_battery "${input_battery[@]}"
