#!/usr/bin/env bash

# The Apple menu, which the macOS menu bar hides under SketchyBar: a click on the apple opens its
# commands, with the same texts, the same actions and the shortcuts, without System Settings, the
# App Store and Recent Items. The rows never change, so the first click adds them and the next ones
# only open the popup, until a reload removes them.
# The apple item runs this with no arguments, each popup row with its command

HELPER="$CONFIG_DIR/helpers/apple_menu"

source "$CONFIG_DIR/colors.sh"

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SHORTCUT_FONT="SF Pro:Medium:12.0"
MIN_WIDTH=220
INSET=4             # between the rows and the edge of the popup, as in the menus of macOS
PADDING=8           # inside the rows
GAP=24              # between a command and its shortcut
ROW_HEIGHT=22

# The texts of the Apple menu in Italian, from macOS (HIToolbox.framework, Menus.loctable)
ABOUT="Informazioni su questo Mac"
FORCE_QUIT="Uscita forzata…"
SLEEP="Standby"
RESTART="Riavvia…"
SHUT_DOWN="Spegni…"
LOCK="Blocca schermo"
LOG_OUT="Esegui il logout da"  # followed by the full name of the user, which render_popup adds

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- SFPro-Medium 12 <text>... prints two widths. SketchyBar measures text only once it draws it,
# but the rows need a fixed width to line up the shortcuts and to highlight a whole row
text_widths() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run(argv) {
  const widths = []
  let group = []
  for (const arg of [...argv, '--']) {
    if (arg !== '--') { group.push(arg); continue }
    const [name, size, ...texts] = group
    const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize(name, Number(size)), $.NSFontAttributeName)
    widths.push(Math.max(0, ...texts.map(text => Math.ceil($(text).sizeWithAttributes(font).width))))
    group = []
  }
  return widths.join(' ')
}
EOF
}

# The popup rows, as in claude.sh: row <name> <properties>... puts one at the bottom. adds and sets
# are the commands that add them and the ones that set them. The rows are INSET from the edges, so
# the highlight doesn't touch them
adds=() sets=()
row() {
  local name="apple.$1"
  shift
  adds+=(--add item "$name" popup.apple)
  sets+=(--set "$name" width=$ROW_WIDTH padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one
space() {
  row "$1" icon.drawing=off label.drawing=off background.drawing=on background.color=$TRANSPARENT \
           background.height=$2
}

# separator <name>: the line between groups of commands. The line is the background of an empty
# icon, as the bars in claude.sh
separator() {
  row "$1" icon.drawing=on icon="" icon.width=$((ROW_WIDTH - 2 * PADDING)) \
           icon.padding_left=0 icon.padding_right=0 icon.background.drawing=on \
           icon.background.color=$SURFACE icon.background.height=1 label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.height=11
  sets+=(padding_left=$((INSET + PADDING)) width=$((ROW_WIDTH - 2 * PADDING)))
}

# command_row <name> <text> [<properties>...]: a command, lit up under the mouse, that runs this with
# its name on click; the properties add its shortcut on the right
command_row() {
  local name="$1" text="$2"
  shift 2
  row "$name" icon.drawing=on icon="$text" icon.font="$FONT" icon.color=$TEXT \
              icon.padding_left=$PADDING icon.padding_right=0 icon.width=$ROW_WIDTH label.drawing=off \
              background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
              background.height=$ROW_HEIGHT script="$0 $name" "$@"
  sets+=(--subscribe "apple.$name" mouse.entered mouse.exited mouse.clicked)
}

# right <shortcut>: sets RIGHT to the properties of the shortcut on the right of a command
right() {
  RIGHT=(icon.width=$((ROW_WIDTH - RIGHT_WIDTH - PADDING)) label.drawing=on label="$1"
         label.font="$SHORTCUT_FONT" label.color=$SUBTEXT label.width=$((RIGHT_WIDTH + PADDING))
         label.align=right label.padding_left=0 label.padding_right=$PADDING)
}

# render_popup [<sketchybar arguments>...]: adds the popup rows, in place of any already there. The
# arguments go in the same command, e.g. to open the popup
render_popup() {
  local log_out widths
  log_out="$LOG_OUT $(id -F)…"
  widths=($(text_widths HelveticaNeue-Bold 13 "$ABOUT" "$FORCE_QUIT" "$SLEEP" "$RESTART" "$SHUT_DOWN" \
                                              "$LOCK" "$log_out" \
                        -- SFPro-Medium 12 "⌥⌘⎋" "⌃⌘Q" "⇧⌘Q"))
  RIGHT_WIDTH=${widths[1]:-0}
  ROW_WIDTH=$((PADDING + ${widths[0]:-0} + GAP + RIGHT_WIDTH + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $ROW_WIDTH ] && ROW_WIDTH=$((MIN_WIDTH - 2 * INSET))

  space top 4
  command_row about "$ABOUT"
  separator separator.about
  right "⌥⌘⎋"
  command_row force_quit "$FORCE_QUIT" "${RIGHT[@]}"
  separator separator.force_quit
  command_row sleep "$SLEEP"
  command_row restart "$RESTART"
  command_row shut_down "$SHUT_DOWN"
  separator separator.shut_down
  right "⌃⌘Q"
  command_row lock "$LOCK" "${RIGHT[@]}"
  right "⇧⌘Q"
  command_row log_out "$log_out" "${RIGHT[@]}"
  space bottom 4

  sketchybar --remove '/apple\..*/' "${adds[@]}" "${sets[@]}" "$@"
}

# loginwindow <event>: the Apple event the Apple menu sends to loginwindow, which shows the Force
# Quit window (apwn) or asks to confirm a restart (rrst), a shut down (rsdn) or a log out (logo)
loginwindow() {
  osascript -e "tell application \"loginwindow\" to «event aevt$1»" > /dev/null 2>&1
}

# run <command>: as in a menu, the popup closes and then the command runs. The row loses its
# highlight, since it won't see the mouse leave
run() {
  sketchybar --set "$NAME" background.color=$TRANSPARENT --set apple popup.drawing=off
  case "$1" in
    about) open "/System/Library/CoreServices/Applications/About This Mac.app" ;;
    force_quit) loginwindow apwn ;;
    sleep) pmset sleepnow > /dev/null ;;
    restart) loginwindow rrst ;;
    shut_down) loginwindow rsdn ;;
    lock) "$HELPER" lock ;;
    log_out) loginwindow logo ;;
  esac
}

# A popup row
if [ "$NAME" != apple ]; then
  case "$SENDER" in
    mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked) run "$@" ;;
  esac
  exit 0
fi

case "$SENDER" in
  mouse.clicked)
    # Whether the popup is open, and whether it has its rows
    case "$(sketchybar --query apple | jq -r '"\(.popup.drawing) \(.popup.items // [] | index("apple.about") != null)"')" in
      on\ *) sketchybar --set apple popup.drawing=off ;;
      *\ true) sketchybar --set apple popup.drawing=on ;;
      *) render_popup --set apple popup.drawing=on ;;
    esac
    ;;
  mouse.exited.global) sketchybar --set apple popup.drawing=off ;;
esac
