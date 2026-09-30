#!/usr/bin/env bash

# Default audio output and input: updates both audio_output and audio_input
# helpers/audio_devices reports their id, transport, type and name; the icons are SF Symbols

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

# icon_for <output|input> <transport> <type> <name>
icon_for() {
  case "$1:$4" in
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

IFS=$'\t' read -r OUT_ID OUT_TRANSPORT OUT_TYPE OUT_NAME < <("$CONFIG_DIR/helpers/audio_devices" output)
IFS=$'\t' read -r IN_ID IN_TRANSPORT IN_TYPE IN_NAME < <("$CONFIG_DIR/helpers/audio_devices" input)

# Same device for both (e.g. Bluetooth headphones): the two icons side by side, then one name.
# Otherwise the items keep the default padding (4) between them
if [ "$OUT_ID" = "$IN_ID" ]; then
  OUT_LABEL=off GAP=0
else
  OUT_LABEL=on GAP=4
fi

output=(drawing=off)
if [ -n "$OUT_ID" ]; then
  output=(drawing=on icon="$(icon_for output "$OUT_TRANSPORT" "$OUT_TYPE" "$OUT_NAME")"
          label="$OUT_NAME" label.drawing=$OUT_LABEL padding_right=$GAP)
fi

input=(drawing=off)
if [ -n "$IN_ID" ]; then
  input=(drawing=on icon="$(icon_for input "$IN_TRANSPORT" "$IN_TYPE" "$IN_NAME")"
         label="$IN_NAME" padding_left=$GAP)
fi

sketchybar --set audio_output "${output[@]}" --set audio_input "${input[@]}"
