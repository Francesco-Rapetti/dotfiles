#!/usr/bin/env bash

# AeroSpace workspaces: the number of each one followed by the icons of its windows,
# the focused one highlighted and the empty ones hidden.
# It runs for the hidden item aerospace and updates all the space.<n> items at once, since a single
# `aerospace list-windows --all` says where every window is. Each window gets an item
# space.<n>.win.<i> after space.<n>, drawing the app icon, and the bracket space.<n>.group
# draws the highlight behind the number and the icons

# A new window sends several events at once: the runs take turns, because each one adds and
# removes items according to the ones it finds in the bar
exec 9> "${TMPDIR:-/tmp}/sketchybar_aerospace.lock"
lockf -s -t 5 9 || exit

SKY=0xff89dceb
BASE=0xff1e1e2e
TEXT=0xffcdd6f4

# The app icon, 19pt at this scale. Windows without a bundle id show the initial of the app instead
window=(
  padding_left=0
  padding_right=0
  background.drawing=on
  background.image.scale=0.6
  label.padding_left=4
  label.padding_right=4
)

group=(
  background.color=$SKY
  background.corner_radius=6
  background.height=22
)

# $FOCUSED_WORKSPACE is only set by the aerospace_workspace_change event,
# so query AeroSpace directly on startup and on the other events
FOCUSED="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"
WINDOWS="$(aerospace list-windows --all --format '%{workspace}|%{window-id}|%{app-bundle-id}|%{app-name}')"
ITEMS="$(sketchybar --query bar | jq -r '.items[]')"

args=()
for sid in 1 2 3 4 5 6 7 8 9; do
  if [ "$sid" = "$FOCUSED" ]; then
    color=$BASE highlight=on
  else
    color=$TEXT highlight=off
  fi

  existing=$(grep -c "^space\.$sid\.win\." <<< "$ITEMS")
  members=(space.$sid)
  windows=()
  while IFS='|' read -r _ id bundle app; do
    i=$((${#members[@]} - 1))
    item=space.$sid.win.$i
    if [ "$i" -ge "$existing" ]; then
      windows+=(--add item $item left --move $item after "${members[$i]}" --set $item "${window[@]}")
    fi
    if [ -n "$bundle" ] && [ "$bundle" != NULL-APP-BUNDLE-ID ]; then
      windows+=(--set $item background.image="app.$bundle" label.drawing=off)
    else
      windows+=(--set $item background.image.drawing=off label="$(tr '[:lower:]' '[:upper:]' <<< "${app:0:1}")" label.drawing=on)
    fi
    windows+=(--set $item padding_right=0 label.color=$color click_script="aerospace focus --window-id $id")
    members+=($item)
  done < <(grep "^$sid|" <<< "$WINDOWS")
  count=$((${#members[@]} - 1))

  # A bracket keeps the members it was created with, so it is created again when they change
  if [ "$count" -ne "$existing" ] || ! grep -qx "space\.$sid\.group" <<< "$ITEMS"; then
    if grep -qx "space\.$sid\.group" <<< "$ITEMS"; then
      args+=(--remove space.$sid.group)
    fi
    for ((i = count; i < existing; i++)); do
      args+=(--remove space.$sid.win.$i)
    done
    args+=("${windows[@]}" --add bracket space.$sid.group "${members[@]}" --set space.$sid.group "${group[@]}")
  else
    args+=("${windows[@]}")
  fi

  # The bracket also covers the padding of its first and last member: the padding_left of the
  # number and the padding_right of the last icon are room inside the highlight
  if [ "$count" -gt 0 ]; then
    args+=(--set space.$sid label.padding_right=4 --set "${members[$count]}" padding_right=8)
  else
    args+=(--set space.$sid label.padding_right=10)
  fi

  if [ "$sid" = "$FOCUSED" ] || [ "$count" -gt 0 ]; then
    drawing=on
  else
    drawing=off
  fi
  args+=(--set space.$sid drawing=$drawing label.color=$color --set space.$sid.group background.drawing=$highlight)
done

sketchybar "${args[@]}"
