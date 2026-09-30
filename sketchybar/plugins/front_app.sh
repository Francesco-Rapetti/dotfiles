#!/bin/sh

# The front_app_switched event passes the name of the focused app in $INFO

if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set "$NAME" label="$INFO"
fi
