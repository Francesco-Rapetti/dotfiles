#!/usr/bin/env bash

# Highlight the focused AeroSpace workspace and hide the empty ones
# $1 is the workspace of the item invoking this script (name $NAME)
# $FOCUSED_WORKSPACE is only set by the aerospace_workspace_change event,
# so query AeroSpace directly on startup and on the other events

WORKSPACE="$1"
FOCUSED="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"

if [ "$WORKSPACE" = "$FOCUSED" ]; then
  sketchybar --set "$NAME" drawing=on background.drawing=on label.color=0xff1e1e2e
elif [ -n "$(aerospace list-windows --workspace "$WORKSPACE")" ]; then
  sketchybar --set "$NAME" drawing=on background.drawing=off label.color=0xffcdd6f4
else
  sketchybar --set "$NAME" drawing=off
fi
