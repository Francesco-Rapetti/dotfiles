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

# stale: whether SketchyBar knows other displays than macOS. Not when it answers nothing
stale() {
  local known
  known="$(known_displays)"
  [ -n "$known" ] && [ "$known" != "$(screens)" ]
}

# SketchyBar may miss the displays changing while the Mac sleeps, e.g. the MacBook's going away
# when it wakes with the lid closed on a monitor: it keeps drawing the bar where the old displays
# were, now on no screen, and --reload doesn't help. So a few seconds after a wake, when the
# displays are back, and whenever the active display changes, its displays are compared with those
# of macOS: if they still differ 5 seconds later, SketchyBar is stopped, and ../start.sh starts it
# again. Only once for the same displays of macOS, in case a SketchyBar just started sees them
# differently too
if [ "$SENDER" = system_woke ] || [ "$SENDER" = display_change ]; then
  [ "$SENDER" = system_woke ] && sleep 10
  if stale && sleep 5 && stale; then
    screens="$(screens)"
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
