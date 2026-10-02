#!/usr/bin/env bash

# AeroSpace workspaces: the number of each one followed by the icons of its windows,
# the focused one highlighted and the empty ones hidden. The focused window has a darker tile
# behind its icon.
# It runs for the hidden item aerospace and updates all the space.<n> items at once, since a single
# `aerospace list-windows --all` says where every window is. Each window gets an item
# space.<n>.win.<i> after space.<n>, drawing the app icon, and the bracket space.<n>.group
# draws the highlight behind the number and the icons.
# AeroSpace lists the windows by app name: helpers/window_order puts those of each workspace in the
# order they have on screen, and remembers it for the workspaces that aren't.
# A window in fullscreen (alt-f) has the fullscreen symbol after its icon, and the windows of the
# apps counted in the green badge of notification.sh a green dot on theirs.
# The item aerospace_mode runs it too: the binding mode, hidden in main. sketchybarrc runs it with
# watch, which follows `aerospace subscribe mode-changed` and triggers aerospace_mode_change with
# the mode: AeroSpace has no callback for the modes, and the bindings that leave service are many

# AeroSpace sends the mode at once and then whenever it changes, as {"_event":"mode-changed",
# "mode":"service"}. If AeroSpace quits, it waits for it to come back
if [ "$1" = watch ]; then
  trap 'pkill -P $$; exit 0' TERM INT HUP
  while :; do
    while read -r event; do
      sketchybar --trigger aerospace_mode_change MODE="$(jq -r .mode <<< "$event")"
    done < <(exec aerospace subscribe mode-changed 2>/dev/null)
    sleep 5 &
    wait $!
  done
fi

# $MODE is only set by the aerospace_mode_change event, so query AeroSpace directly on startup
if [ "$NAME" = aerospace_mode ]; then
  mode="${MODE:-$(aerospace list-modes --current)}"
  if [ "$mode" = main ]; then
    sketchybar --set "$NAME" drawing=off
  else
    sketchybar --set "$NAME" drawing=on label="$mode"
  fi
  exit 0
fi

# A new window sends several events at once: the runs take turns, because each one adds and
# removes items according to the ones it finds in the bar
exec 9> "${TMPDIR:-/tmp}/sketchybar_aerospace.lock"
lockf -s -t 5 9 || exit

source "$CONFIG_DIR/colors.sh"
# BASE at 35% on PRIMARY, the tile of the focused window
TILE=0x59${BASE#0xff}

# The app icon, 19pt at this scale, centered in the 23pt of the icon: the room around it shows
# the tile, which is the background of the item. The icon is empty, or the initial of the app for
# the windows without a bundle id. The label is the fullscreen symbol, on the tile too, drawn only
# for the window in fullscreen.
# Not width=23: with a fixed width SketchyBar leaves out the padding_right of the last icon when it
# places the next number, but the bracket still covers it
window=(
  padding_left=0
  padding_right=0
  background.drawing=on
  background.height=20
  background.corner_radius=5
  background.image.scale=0.6
  background.image.padding_left=2
  icon.drawing=on
  icon.font="Helvetica Neue:Bold:13.0"
  icon.width=23
  icon.align=center
  icon.padding_left=0
  icon.padding_right=0
  label=􀅊  # arrow.up.left.and.arrow.down.right
  label.font="SF Pro:Heavy:11.0"
  label.padding_left=0
  label.padding_right=4
)
# The icon of the windows with an app icon, empty, and of the others, the initial of the app
letter=(icon.font="Helvetica Neue:Bold:13.0" icon.align=center icon.y_offset=0)
# The app has notifications to read, those of the green badge of notification.sh: a green dot, the
# icon of the window, on the top right corner of the app icon as the badges of the Dock
dot=(icon=􀀁 icon.font="SF Pro:Heavy:7.0" icon.align=right icon.y_offset=6 icon.color=$GREEN)  # circle.fill
# The bundle id of each app with a badge, one per line, which notification.sh saves
BADGED=$'\n'"$(cat "${TMPDIR:-/tmp}/sketchybar_notification_badged" 2>/dev/null)"$'\n'

# Inside the pill of the workspaces (the bracket spaces of sketchybarrc), 3pt from its edges: the
# corner radius is the pill's less 3
group=(
  background.color=$PRIMARY
  background.corner_radius=7
  background.height=22
)

# window_order takes a while, waiting for the windows to stop moving: it runs alongside the other
# queries
exec 3< <(aerospace list-windows --all --format '%{workspace}|%{window-id}|%{window-is-fullscreen}|%{app-bundle-id}|%{app-name}' \
            | "$CONFIG_DIR/helpers/window_order" "${TMPDIR:-/tmp}/sketchybar_aerospace_order")
# $FOCUSED_WORKSPACE is only set by the aerospace_workspace_change event,
# so query AeroSpace directly on startup and on the other events
FOCUSED="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"
# Empty when the focused workspace has no windows
FOCUSED_WINDOW="$(aerospace list-windows --focused --format '%{window-id}' 2> /dev/null)"
# --query answers nothing while SketchyBar is busy, e.g. adding the rows of a popup: without the
# items this would add again the ones that are there, and leave the old ones
for ((i = 0; i < 25; i++)); do
  ITEMS="$(sketchybar --query bar | jq -r '.items[]')"
  [ -n "$ITEMS" ] && break
  sleep 0.1
done
[ -n "$ITEMS" ] || exit
WINDOWS="$(cat <&3)"

args=()
for sid in 1 2 3 4 5 6 7 8 9; do
  if [ "$sid" = "$FOCUSED" ]; then
    color=$ON_PRIMARY highlight=on
  else
    color=$TEXT highlight=off
  fi

  existing=$(grep -c "^space\.$sid\.win\." <<< "$ITEMS")
  members=(space.$sid)
  windows=()
  while IFS='|' read -r _ id fullscreen bundle app; do
    i=$((${#members[@]} - 1))
    item=space.$sid.win.$i
    if [ "$i" -ge "$existing" ]; then
      windows+=(--add item $item left --move $item after "${members[$i]}" --set $item "${window[@]}")
    fi
    if [ -n "$bundle" ] && [ "$bundle" != NULL-APP-BUNDLE-ID ]; then
      windows+=(--set $item background.image="app.$bundle" "${letter[@]}" icon="")
    else
      windows+=(--set $item background.image.drawing=off "${letter[@]}"
                icon="$(tr '[:lower:]' '[:upper:]' <<< "${app:0:1}")")
    fi
    if [ "$id" = "$FOCUSED_WINDOW" ]; then
      tile=$TILE
    else
      tile=0x00000000
    fi
    if [ "$fullscreen" = true ]; then
      full=on
    else
      full=off
    fi
    windows+=(--set $item padding_right=0 background.color=$tile icon.color=$color label.color=$color
              label.drawing=$full click_script="aerospace focus --window-id $id")
    if [ -n "$bundle" ] && [[ $BADGED == *$'\n'"$bundle"$'\n'* ]]; then
      windows+=(--set $item "${dot[@]}")
    fi
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
  # number and the padding_right of the last icon are room inside the highlight. The icons already
  # have 2pt of room on each side
  if [ "$count" -gt 0 ]; then
    args+=(--set space.$sid label.padding_right=2 --set "${members[$count]}" padding_right=6)
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
