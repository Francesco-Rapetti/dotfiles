#!/usr/bin/env bash

# Screenshots of SketchyBar for the README, with made-up data. The plugins of ../sketchybar run as
# SketchyBar runs them, on the bar on the screen, but the helpers and the commands they read are
# those of mock/ and the events carry the data below: so the screenshots show neither the real
# Wi-Fi, events, devices and accounts nor what is on the screen (capture.swift takes only the
# windows of SketchyBar). Meanwhile the bar doesn't update itself (updates=off), and at the end
# sketchybar --reload puts it back as it was.
# Usage: screenshots/take.sh [<shot>...]   all the shots, or only the ones named, e.g. take.sh battery
# Each shot is <shot>.png in this folder. A new plugin needs its made-up data in mock/ or below and
# a shot_<name> function, listed in SHOTS.
# capture.swift needs the Screen Recording permission of the app this runs in, e.g. Terminal

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
MOCK="$DIR/mock"
CAPTURE="$DIR/capture"

SHOTS=(bar apple workspaces home system claude audio network battery calendar clock brew)
# The items of the two sides of the bar, for the shot of the whole bar
LEFT=(apple spaces front_app)
RIGHT=(home_printer home system claude audio network battery calendar clock brew)

# The time of the screenshots: today at 14:10, for the clock, the events and the resets of Claude.
# Today, since the calendar of the clock is drawn for the real one
MOCK_NOW="$(date -j -f %H:%M:%S 14:10:00 +%s)"

fail() {
  echo "take.sh: $1" >&2
  exit 1
}

for shot in "$@"; do
  [[ " ${SHOTS[*]} " == *" $shot "* ]] || fail "shot sconosciuto: $shot (ci sono: ${SHOTS[*]})"
done
[ $# -gt 0 ] && SHOTS=("$@")
pgrep -qx sketchybar || fail "SketchyBar non è in esecuzione"

if [ ! -x "$CAPTURE" ] || [ "$CAPTURE.swift" -nt "$CAPTURE" ]; then
  swiftc -O "$CAPTURE.swift" -o "$CAPTURE" || exit 1
fi

# The CONFIG_DIR of the plugins: the real config, with the helpers of mock/ in place of the real
# ones, among the images that sketchybarrc made, and next to the Brewfile as in the repo. TMPDIR keeps
# their locks and caches apart from those of the bar, and has the states of Home Assistant
WORK="$(mktemp -d)"
CONFIG="$WORK/sketchybar"
mkdir -p "$CONFIG/helpers" "$WORK/tmp"
ln -s "$REPO/sketchybar/colors.sh" "$REPO/sketchybar/plugins" "$MOCK/home_assistant.conf" "$CONFIG/"
ln -s "$REPO/sketchybar/helpers/"* "$CONFIG/helpers/"
ln -sf "$MOCK/helpers/"* "$CONFIG/helpers/"
ln -s "$REPO/Brewfile" "$WORK/"
cp "$MOCK/home_assistant.json" "$WORK/tmp/sketchybar_home_assistant.json"

restore() {
  sketchybar --reload
  rm -rf "$WORK"
}
trap restore EXIT

# settle <pattern>: waits until no plugin whose command line matches is running, e.g. the refresh
# that claude.sh and brew.sh run in the background, for up to the 60 seconds SketchyBar gives them
settle() {
  local i
  for ((i = 0; i < 300; i++)); do
    pgrep -qf "$1" || return 0
    sleep 0.2
  done
}

# run <plugin> <NAME> <SENDER> [<variable>=<value>...] [-- <argument>...]: the plugin as SketchyBar
# runs it, with the commands of mock/bin and the HOME of mock/home
run() {
  local plugin=$1 name=$2 sender=$3 variables=()
  shift 3
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    variables+=("$1")
    shift
  done
  [ "$1" = -- ] && shift
  env PATH="$MOCK/bin:$PATH" HOME="$MOCK/home" TMPDIR="$WORK/tmp" CONFIG_DIR="$CONFIG" MOCK_NOW="$MOCK_NOW" \
      NAME="$name" SENDER="$sender" "${variables[@]}" "$CONFIG/plugins/$plugin.sh" "$@"
}

# query <item>: sketchybar --query, which answers nothing while SketchyBar is busy, e.g. adding the
# rows of a popup and their windows
query() {
  local answer i
  for ((i = 0; i < 50; i++)); do
    answer="$(sketchybar --query "$1")"
    [ -n "$answer" ] && echo "$answer" && return
    sleep 0.2
  done
  return 1
}

# rects <item>...: the rect around the items on each display, as capture takes them; the hidden
# ones are off screen
rects() {
  local item
  for item in "$@"; do
    query "$item"
  done | jq -rs '
    [.[].bounding_rects // {} | to_entries[] | select(.value.origin[0] > -9000)]
    | group_by(.key)[] | map(.value)
    | (map(.origin[0]) | min) as $x | (map(.origin[1]) | min) as $y
    | (map(.origin[0] + .size[0]) | max) as $right | (map(.origin[1] + .size[1]) | max) as $bottom
    | "\($x),\($y),\($right - $x),\($bottom - $y)"'
}

# capture <shot> [--popup] <rect>...: <shot>.png. The rows that the plugins added to a popup
# update until updates=off, e.g. the one under the mouse
capture() {
  local shot=$1
  shift
  sketchybar --set '/.*/' updates=off
  query bar > /dev/null
  sleep 0.5
  "$CAPTURE" "$DIR/$shot.png" "$@" && echo "$DIR/$shot.png"
}

# snap <shot> <item with the popup, or ""> <item>...: <shot>.png with the items, and the popup open
snap() {
  local shot=$1 popup=$2
  shift 2
  if [ -z "$popup" ]; then
    capture "$shot" $(rects "$@")
    return
  fi
  sketchybar --set "$popup" popup.drawing=on
  capture "$shot" --popup $(rects "$@")
  local status=$?
  sketchybar --set "$popup" popup.drawing=off
  return $status
}

# The data of the events that the helpers trigger. CPU, GPU and memory, with the details of the
# popup: the apps in tenths of a percent and in MB, the bundle id, the name and the value separated
# by \x1f
SYSTEM=(
  CPU=23 GPU=8 RAM=62 PRESSURE=normal
  CPU_SYSTEM=71 CPU_USER=162 CPU_IDLE=767
  CPU_TOP=$'com.apple.Safari\x1fSafari\x1f68\ncom.apple.Music\x1fMusica\x1f31\n\x1fWindowServer\x1f24\ncom.apple.Terminal\x1fTerminale\x1f12\n\x1fkernel_task\x1f9'
  GPU_MODEL="Apple M4 Pro" GPU_CORES=16
  GPU_TOP=$'\x1fWindowServer\x1f42\ncom.apple.Safari\x1fSafari\x1f21\ncom.apple.Music\x1fMusica\x1f6'
  MEMORY_USED=15155 MEMORY_TOTAL=24576 MEMORY_APP=9830 MEMORY_WIRED=3277 MEMORY_COMPRESSED=2048 SWAP_USED=0
  MEMORY_TOP=$'com.apple.Safari\x1fSafari\x1f2150\ncom.apple.Music\x1fMusica\x1f612\ncom.apple.mail\x1fMail\x1f430\ncom.apple.Terminal\x1fTerminale\x1f180\ncom.apple.Notes\x1fNote\x1f165'
)
# The next event at MOCK_NOW, and the events of the day: the state, the time, the title, the Meet
# call and the link to Calendar, separated by \x1f
CALENDAR=(
  KIND=upcoming
  LABEL="14:30  Revisione design · tra 20 min"
  EVENTS=$'allday\x1fTutto il giorno\x1fCompleanno di Luca\x1f\x1fical://ekevent/1\npast\x1f09:30 – 10:00\x1fStandup\x1fhttps://meet.google.com/abc-defg-hij\x1fical://ekevent/2\npast\x1f12:30 – 13:30\x1fPranzo con Giulia\x1f\x1fical://ekevent/3\nupcoming\x1f14:30 – 15:30\x1fRevisione design\x1fhttps://meet.google.com/xyz-abcd-efg\x1fical://ekevent/4\nupcoming\x1f18:00 – 19:00\x1fPalestra\x1f\x1fical://ekevent/5'
)

# Every item with its made-up data, as after the first run of each plugin. The bar stops updating
# first, once the runs it has started are over
mock_bar() {
  sketchybar --set '/.*/' updates=off
  settle '/plugins/[a-z_]*\.sh'
  run aerospace aerospace forced
  run front_app front_app front_app_switched INFO=Safari
  run home home forced
  run system cpu system_stats_change "${SYSTEM[@]}"
  run claude claude claude_update
  run audio audio_output forced
  run network network forced
  run battery battery forced
  run calendar calendar calendar_change "${CALENDAR[@]}"
  run clock clock routine
  run brew brew brew_update
  settle "$CONFIG/plugins/"
}

# The shots: the whole bar, its two sides one next to the other, then each item with its popup
shot_bar() { capture bar $(rects "${LEFT[@]}") $(rects "${RIGHT[@]}"); }
shot_apple() {
  run apple apple mouse.clicked
  run apple apple.recent mouse.clicked -- recent
  snap apple apple apple
}
shot_workspaces() { snap workspaces "" spaces front_app; }
shot_home() { snap home home home_printer home; }
shot_system() { snap system cpu system; }
shot_claude() { snap claude claude claude; }
shot_audio() { snap audio audio_output audio; }
shot_network() { snap network "" network; }
shot_battery() {
  run battery battery mouse.clicked
  snap battery battery battery
}
shot_calendar() { snap calendar calendar calendar; }
shot_clock() {
  run clock clock mouse.clicked
  snap clock clock clock
}
shot_brew() { snap brew brew brew; }

mock_bar
for shot in "${SHOTS[@]}"; do
  "shot_$shot" || fail "shot $shot non riuscito"
done
