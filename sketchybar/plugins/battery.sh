#!/bin/sh

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

if [ "$CHARGING" != "" ]; then
  LABEL="⚡ ${PERCENTAGE}%"
else
  LABEL="${PERCENTAGE}%"
fi

sketchybar --set "$NAME" label="$LABEL"
