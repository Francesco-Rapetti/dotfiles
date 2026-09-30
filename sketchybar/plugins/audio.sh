#!/usr/bin/env bash

# Default audio output and input: updates audio_output and audio_input, each followed by the
# battery of the device (audio_output_battery, audio_input_battery) when it has one, or only the
# output when they are the same device or the Mac's own speakers and microphone.
# helpers/audio_devices reports their id, transport, type, name and battery (Bluetooth only);
# the icons are SF Symbols, except for those SF Symbols doesn't have, images that sketchybarrc
# makes: the Galaxy Buds out of a photo (helpers/galaxy_buds_icon.js), and the Mac, a display or
# audio glasses with a speaker badge, a microphone badge or both (helpers/audio_icons.js)

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

SUBTEXT=0xffa6adc8
RED=0xfff38ba8

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

IFS=$'\t' read -r OUT_ID OUT_TRANSPORT OUT_TYPE OUT_NAME OUT_BATTERY < <("$CONFIG_DIR/helpers/audio_devices" output)
IFS=$'\t' read -r IN_ID IN_TRANSPORT IN_TYPE IN_NAME IN_BATTERY < <("$CONFIG_DIR/helpers/audio_devices" input)

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
  output=(drawing=on "${ICON[@]}" label="$OUT_NAME")
fi

input=(drawing=off)
if [ -n "$IN_ID" ]; then
  icon_settings "$(icon input microphone "$IN_TRANSPORT" "$IN_TYPE" "$IN_NAME")"
  input=(drawing=on "${ICON[@]}" label="$IN_NAME")
fi

[ -n "$OUT_ID" ] || OUT_BATTERY=""
[ -n "$IN_ID" ] || IN_BATTERY=""
read -ra output_battery <<< "$(battery_for "$OUT_BATTERY")"
read -ra input_battery <<< "$(battery_for "$IN_BATTERY")"

sketchybar --set audio_output "${output[@]}" --set audio_output_battery "${output_battery[@]}" \
           --set audio_input "${input[@]}" --set audio_input_battery "${input_battery[@]}"
