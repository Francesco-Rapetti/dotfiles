#!/usr/bin/env bash

# CPU, GPU and memory usage, which helpers/system_stats sends with system_stats_change every 2
# seconds when they change. CPU and GPU turn yellow from 75% and red from 90%; the memory has the
# color of its pressure, as in Activity Monitor: macOS keeps the memory nearly full with caches and
# compressed pages, so the percentage alone says little. The GPU hides when macOS doesn't report it.
# The cpu item runs this for all three
# The icons are SF Symbols, so they need the SF Pro font (brew install --cask font-sf-pro)

TEXT=0xffcdd6f4
YELLOW=0xfff9e2af
RED=0xfff38ba8

WARNING=75   # from this percentage CPU and GPU turn yellow
CRITICAL=90  # and from this one red

[ "$SENDER" = "system_stats_change" ] || exit 0

color_for() {
  if [ "$1" -ge $CRITICAL ]; then
    echo $RED
  elif [ "$1" -ge $WARNING ]; then
    echo $YELLOW
  else
    echo $TEXT
  fi
}

case "$PRESSURE" in
  warning) RAM_COLOR=$YELLOW ;;
  critical) RAM_COLOR=$RED ;;
  *) RAM_COLOR=$TEXT ;;
esac

sets=()
if [ -n "$CPU" ]; then
  color=$(color_for "$CPU")
  sets+=(--set cpu label="$CPU%" icon.color=$color label.color=$color)
fi
if [ -n "$GPU" ]; then
  color=$(color_for "$GPU")
  sets+=(--set gpu drawing=on label="$GPU%" icon.color=$color label.color=$color)
else
  sets+=(--set gpu drawing=off)
fi
[ -n "$RAM" ] && sets+=(--set ram label="$RAM%" icon.color=$RAM_COLOR label.color=$RAM_COLOR)

sketchybar "${sets[@]}"
