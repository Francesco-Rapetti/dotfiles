#!/usr/bin/env bash

# Shows some items only on the displays without a notch: on a MacBook's, the items on the right
# would end up under it (see sketchybarrc). The display property of SketchyBar takes the
# arrangement ids of `sketchybar --query displays`, which change as displays come and go.
# display_change fires then but also whenever another display becomes the active one, so the items
# change only when the displays do, or at startup. NSScreen tells which displays have a notch: the
# top of their safe area, which macOS keeps free of windows

# CPU and GPU, so that the memory stays alone, the names of the audio devices, of the Wi-Fi and of
# the VPN, so that their icons stay, the title of the event, so that its time stays, and the date,
# so that the hour stays
ITEMS=(cpu gpu audio_output_name audio_input_name network_name network_vpn_name calendar_title clock_date)
DISPLAYS="${TMPDIR:-/tmp}/sketchybar_displays.json"
RESTARTED="${TMPDIR:-/tmp}/sketchybar_displays_restarted"  # the displays of macOS at the last restart
LOG="$HOME/Library/Logs/sketchybar-crash.log"  # the one of ../start.sh

# known_displays: the DirectDisplayID and the frame (x y w h) of each display SketchyBar knows, one
# per line
known_displays() {
  sketchybar --query displays | jq -r '.[] | [.DirectDisplayID, (.frame | .x, .y, .w, .h | round)] | join(" ")' \
    | sort -n
}

# screens: the same for the displays of macOS, from NSScreen, whose frames start at the bottom left
# of the main display rather than at the top left
screens() {
  osascript -l JavaScript - <<'EOF' | sort -n
ObjC.import('AppKit')
function run() {
  const screens = $.NSScreen.screens
  const height = screens.objectAtIndex(0).frame.size.height
  const lines = []
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i), frame = screen.frame
    lines.push([screen.deviceDescription.objectForKey('NSScreenNumber').js, frame.origin.x,
      height - frame.origin.y - frame.size.height, frame.size.width, frame.size.height].map(Math.round).join(' '))
  }
  return lines.join('\n')
}
EOF
}

# watch <checks> [stop]: compares the displays of SketchyBar with those of macOS every INTERVAL
# seconds, that many times at most, and succeeds as soon as they have differed for SETTLE checks in
# a row while those of macOS stayed the same. With stop it fails as soon as they are the same.
# SketchyBar answering nothing counts as the same. Sets SCREENS to the displays of macOS
watch() {
  local i known previous="" count=0
  for ((i = 0; i < $1; i++)); do
    [ $i -gt 0 ] && sleep $INTERVAL
    known="$(known_displays)"
    SCREENS="$(screens)"
    if [ -z "$known" ] || [ "$known" = "$SCREENS" ]; then
      [ "$2" = stop ] && return 1
      count=0
    elif [ "$SCREENS" = "$previous" ]; then
      count=$((count + 1))
    else
      count=1
    fi
    [ $count -ge $SETTLE ] && return 0
    previous="$SCREENS"
  done
  return 1
}

# SketchyBar may miss the displays changing while the Mac sleeps, e.g. the MacBook's going away
# when it wakes with the lid closed on a monitor: it keeps drawing the bar where the old displays
# were, now on no screen, and --reload doesn't help. So its displays are compared with those of
# macOS: for 20 seconds after a wake, since the displays come back one at a time, and whenever the
# active display changes, until they are the same (most times at the first check). If they still
# differ after SETTLE checks, SketchyBar is stopped, and ../start.sh starts it again: a few seconds
# after the displays settle, often before the password is in. Only once for the same displays of
# macOS, in case a SketchyBar just started sees them differently too. Each check is an osascript,
# ~0.05 s of CPU: every 2 seconds rather than every second, to keep a wake light
INTERVAL=2
WAKE_CHECKS=10
CHANGE_CHECKS=5
SETTLE=2
if [ "$SENDER" = system_woke ] || [ "$SENDER" = display_change ]; then
  if [ "$SENDER" = system_woke ]; then
    watch $WAKE_CHECKS
  else
    watch $CHANGE_CHECKS stop
  fi
  if [ $? -eq 0 ]; then
    screens="$SCREENS"
    if [ "$screens" != "$(cat "$RESTARTED" 2>/dev/null)" ] && pgrep -qf 'sketchybar/start\.sh'; then
      echo "$screens" > "$RESTARTED"
      entry="$(
        echo "=== $(date '+%d/%m/%Y %H:%M:%S') ==="
        echo "SketchyBar conosceva schermi diversi da quelli di macOS ed è ripartito (id x y larghezza altezza)."
        echo "SketchyBar:"
        known_displays | sed 's/^/  /'
        echo "macOS:"
        sed 's/^/  /' <<< "$screens"
      )"
      { printf '%s\n\n' "$entry"; cat "$LOG" 2>/dev/null; } > "$LOG.$$"
      mv "$LOG.$$" "$LOG"
      pkill -x sketchybar
      exit 0
    fi
  else
    rm -f "$RESTARTED"
  fi
fi

# --query answers nothing while SketchyBar is busy, e.g. at startup
for ((i = 0; i < 25; i++)); do
  displays="$(sketchybar --query displays)"
  [ -n "$displays" ] && break
  sleep 0.2
done
[ -n "$displays" ] || exit 1
[ "$SENDER" != forced ] && [ "$displays" = "$(cat "$DISPLAYS" 2>/dev/null)" ] && exit 0
echo "$displays" > "$DISPLAYS"

# The DirectDisplayID of the displays with a notch, e.g. 1 or 1,3
notched="$(osascript -l JavaScript - <<'EOF'
ObjC.import('AppKit')
function run() {
  const screens = $.NSScreen.screens
  const ids = []
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i)
    if (screen.safeAreaInsets.top > 0) ids.push(screen.deviceDescription.objectForKey('NSScreenNumber').js)
  }
  return ids.join(',')
}
EOF
)"

# The others by arrangement, e.g. 2 or 1,3. Without any, a display that isn't there, as SketchyBar
# does for the spaces of no display
wide="$(jq -r --arg notched "$notched" '
  ($notched | split(",") | map(tonumber)) as $ids
  | [.[] | select(.DirectDisplayID | IN($ids[]) | not) | ."arrangement-id"]
  | if length > 0 then join(",") else 30 end' <<< "$displays")"

items=()
for item in "${ITEMS[@]}"; do
  items+=(--set "$item" display="$wide")
done
sketchybar "${items[@]}"
