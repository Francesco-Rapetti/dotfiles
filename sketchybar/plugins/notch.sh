#!/usr/bin/env bash

# Shows some items only on the displays without a notch: on a MacBook's, the items on the right
# would end up under it (see sketchybarrc); and some only on the large displays. The display
# property of SketchyBar takes the arrangement ids of `sketchybar --query displays`, which change as
# displays come and go. display_change fires then but also whenever another display becomes the
# active one, so the items change only when the displays do, or at startup. NSScreen tells which
# displays have a notch, the top of their safe area, which macOS keeps free of windows, and how wide
# each one is

# CPU and GPU, so that the memory stays alone, the names of the audio devices, of the Wi-Fi and of
# the VPN, so that their icons stay, the title of the event, so that its time stays, and the date,
# so that the hour stays
ITEMS=(cpu gpu audio_output_name audio_input_name network_name network_vpn_name calendar_title clock_date)
# With more than one Claude account (see sketchybarrc), the item of each, claude, claude_2,
# claude_3..., is only on the large displays, at least this wide in points, e.g. a 49" 32:9 one
# (5120); on the others, where they would make the bar too long, there is claude_all in their place
CLAUDE_ITEMS='^claude(_[0-9]+)?$'
LARGE_WIDTH=3840
DISPLAYS="${TMPDIR:-/tmp}/sketchybar_displays.json"
RESTARTED="${TMPDIR:-/tmp}/sketchybar_displays_restarted"  # the displays of macOS at the last restart
LOG="$HOME/Library/Logs/sketchybar-crash.log"  # the one of ../start.sh

# screens <margin> <height>: as JSON, the displays of macOS, from NSScreen, and the bars of
# SketchyBar: its windows as tall as the bar and wider than half the narrowest display, which the
# items aren't. Each display has its DirectDisplayID, its frame (x y w h from the top left of the
# main display, as in SketchyBar, while NSScreen starts at the bottom left) and whether a bar is on
# it: as wide as the display less the margins, at any height in it, since a menu bar that doesn't
# hide or y_offset moves it down. Off screen too, as on a display showing an app in full screen
screens() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
ObjC.import('CoreGraphics')
function run(argv) {
  const [margin, height] = argv.map(Number)
  const screens = $.NSScreen.screens
  const main = screens.objectAtIndex(0).frame.size.height
  const displays = []
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i), frame = screen.frame
    displays.push({id: screen.deviceDescription.objectForKey('NSScreenNumber').js, frame: [frame.origin.x,
      main - frame.origin.y - frame.size.height, frame.size.width, frame.size.height].map(Math.round)})
  }
  const narrowest = Math.min(...displays.map(display => display.frame[2]))
  const bars = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)))
    .map(window => window.kCGWindowOwnerName === 'sketchybar' && window.kCGWindowBounds)
    .filter(bounds => bounds && bounds.Height === height && bounds.Width > narrowest / 2)
    .map(bounds => [bounds.X, bounds.Y, bounds.Width, bounds.Height].map(Math.round))
  for (const display of displays) {
    const [x, y, w, h] = display.frame
    display.bar = bars.some(([barX, barY, barW]) => barX === x + margin && barW === w - 2 * margin && barY >= y && barY < y + h)
  }
  return JSON.stringify({displays: displays.sort((a, b) => a.id - b.id), bars})
}
EOF
}

# watch <checks> [stop]: checks every INTERVAL seconds, that many times at most, that SketchyBar has
# a bar on each display of macOS, and succeeds as soon as one has had none for SETTLE checks in a
# row while the displays stayed the same. With stop it fails as soon as each has one. SketchyBar or
# osascript answering nothing counts as each having one. Sets SCREENS to the last screens
watch() {
  local i bar current previous="" count=0
  for ((i = 0; i < $1; i++)); do
    [ $i -gt 0 ] && sleep $INTERVAL
    bar="$(sketchybar --query bar)"
    [ -n "$bar" ] && SCREENS="$(screens $(jq -r '.margin, .height' <<< "$bar"))"
    if [ -n "$bar" ] && jq -e 'any(.displays[]; .bar | not)' <<< "$SCREENS" > /dev/null 2>&1; then
      current="$(jq -c '.displays | map(del(.bar))' <<< "$SCREENS")"
      if [ "$current" = "$previous" ]; then
        count=$((count + 1))
      else
        count=1
      fi
      previous="$current"
    else
      [ "$2" = stop ] && return 1
      count=0
    fi
    [ $count -ge $SETTLE ] && return 0
  done
  return 1
}

# SketchyBar may miss the displays changing: while the Mac sleeps, e.g. the MacBook's going away
# when it wakes with the lid closed on a monitor, but also awake, e.g. a monitor that goes off and
# comes back a few seconds later. It keeps drawing the bar where the old displays were, on no screen
# or on part of one, and --reload doesn't help. --query displays doesn't tell: after a wake with the
# lid closed on two monitors, which left a single bar as wide as the second monitor at the top left
# of the first, off screen, it listed the displays of macOS all the same. So whether each display of
# macOS has a bar is checked from the windows of SketchyBar: for 20 seconds after a wake and after
# macOS changes the displays, since they come back one at a time, and whenever the active display
# changes, until each has one (most times at the first check). The change comes from
# helpers/display_changes (macos_display_change), another process, since SketchyBar that misses it
# doesn't trigger display_change either. If one still has none after SETTLE checks, SketchyBar is
# stopped, and ../start.sh starts it again: a few seconds after the displays settle, often before
# the password is in. Only once for the same displays of macOS, in case a SketchyBar just started
# misses them too. Each check is an osascript, ~0.05 s of CPU: every 2 seconds rather than every
# second, to keep a wake light
INTERVAL=2
WAKE_CHECKS=10
CHANGE_CHECKS=5
SETTLE=2
if [ "$SENDER" = system_woke ] || [ "$SENDER" = macos_display_change ] || [ "$SENDER" = display_change ]; then
  if [ "$SENDER" = display_change ]; then
    watch $CHANGE_CHECKS stop
  else
    watch $WAKE_CHECKS
  fi
  if [ $? -eq 0 ]; then
    screens="$(jq -c '.displays | map(del(.bar))' <<< "$SCREENS")"
    # -a: start.sh and sketchybar are ancestors of this script, and without it pgrep and pkill
    # leave out their ancestors
    if [ "$screens" != "$(cat "$RESTARTED" 2>/dev/null)" ] && pgrep -aqf 'sketchybar/start\.sh'; then
      echo "$screens" > "$RESTARTED"
      entry="$(
        echo "=== $(date '+%d/%m/%Y %H:%M:%S') ==="
        echo "SketchyBar non aveva la barra su tutti gli schermi ed è ripartito (x y larghezza altezza)."
        jq -r '"Schermi di macOS:",
               (.displays[] | "  \(.frame | join(" ")) (id \(.id))\(if .bar then "" else ", senza barra" end)"),
               "Barre di SketchyBar:",
               (.bars[] | "  " + join(" ")),
               (if .bars == [] then "  nessuna" else empty end)' <<< "$SCREENS"
      )"
      { printf '%s\n\n' "$entry"; cat "$LOG" 2>/dev/null; } > "$LOG.$$"
      mv "$LOG.$$" "$LOG"
      pkill -ax sketchybar
      exit 0
    fi
  else
    rm -f "$RESTARTED"
  fi
fi

# query <displays|bar>: --query answers nothing while SketchyBar is busy, e.g. at startup
query() {
  local answer i
  for ((i = 0; i < 25; i++)); do
    answer="$(sketchybar --query "$1")"
    [ -n "$answer" ] && echo "$answer" && return
    sleep 0.2
  done
  return 1
}
displays="$(query displays)" || exit 1
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

# arrangement <DirectDisplayIDs> <true|false>: the arrangement ids of those displays, or with false
# of the others, e.g. 2 or 1,3. Without any, a display that isn't there, as SketchyBar does for the
# spaces of no display
arrangement() {
  jq -r --arg ids "$1" --argjson among "$2" '
    ($ids | split(",") | map(tonumber)) as $ids
    | [.[] | select((.DirectDisplayID | IN($ids[])) == $among) | ."arrangement-id"]
    | if length > 0 then join(",") else 30 end' <<< "$displays"
}

# The displays without a notch
wide="$(arrangement "$notched" false)"

# The DirectDisplayID of the large displays, e.g. 2
large="$(osascript -l JavaScript - $LARGE_WIDTH <<'EOF'
ObjC.import('AppKit')
function run([minWidth]) {
  const screens = $.NSScreen.screens
  const ids = []
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i)
    if (screen.frame.size.width >= Number(minWidth)) ids.push(screen.deviceDescription.objectForKey('NSScreenNumber').js)
  }
  return ids.join(',')
}
EOF
)"
small="$(arrangement "$large" false)"
large="$(arrangement "$large" true)"

items=()
for item in "${ITEMS[@]}"; do
  items+=(--set "$item" display="$wide")
done
# Only with claude_all, which is there with more than one account
bar="$(query bar)"
if jq -e '.items | index("claude_all")' <<< "$bar" > /dev/null; then
  for item in $(jq -r --arg pattern "$CLAUDE_ITEMS" '.items[] | select(test($pattern))' <<< "$bar"); do
    items+=(--set "$item" display="$large")
  done
  items+=(--set claude_all display="$small")
fi
sketchybar "${items[@]}"
