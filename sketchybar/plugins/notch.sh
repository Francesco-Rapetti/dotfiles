#!/usr/bin/env bash

# Shows some items only on the displays without a notch: on a MacBook's, the items on the right
# would end up under it (see sketchybarrc). The display property of SketchyBar takes the
# arrangement ids of `sketchybar --query displays`, which change as displays come and go.
# display_change fires then but also whenever another display becomes the active one, so the items
# change only when the displays do, or at startup. NSScreen tells which displays have a notch: the
# top of their safe area, which macOS keeps free of windows

# CPU and GPU, so that the memory stays alone, the name of the VPN, so that its shield stays, and the
# title of the event, so that its time stays
ITEMS=(cpu gpu network_vpn_name calendar_title)
DISPLAYS="${TMPDIR:-/tmp}/sketchybar_displays.json"

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
