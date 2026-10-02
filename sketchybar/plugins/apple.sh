#!/usr/bin/env bash

# The Apple menu, which the macOS menu bar hides under SketchyBar: a click on the apple opens its
# commands, with the same texts and the same actions, the badges of System Settings and of the App
# Store and the shortcuts. Recent Items opens inside the popup, under its row: a popup of a popup
# row opens beside it, but moving the mouse there counts as leaving both (mouse.exited.global).
# The apple item runs this with no arguments, each popup row with its command

HELPER="$CONFIG_DIR/helpers/apple_menu"
ICONS="${TMPDIR:-/tmp}/sketchybar_recent_items"

source "$CONFIG_DIR/colors.sh"

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
SHORTCUT_FONT="SF Pro:Medium:12.0"
BADGE_FONT="Helvetica Neue:Bold:11.0"
CHEVRON_RIGHT=􀆊  # chevron.right
CHEVRON_DOWN=􀆈   # chevron.down
MIN_WIDTH=220
MAX_NAME_WIDTH=280  # of a recent item: a longer name loses its middle, as in the real menu
INSET=4             # between the rows and the edge of the popup, as in the menus of macOS
PADDING=8           # inside the rows
GAP=24              # between a command and its shortcut or badge
INDENT=12           # of Recent Items under its row
ICON_SIZE=16        # of the recent items; the helper draws them at 4 px per point
ICON_GAP=6          # between the icon and the name of a recent item
ROW_HEIGHT=22
BADGE_HEIGHT=16
DIGIT_WIDTH=6       # every digit of BADGE_FONT, as in notification.sh

# The texts of the Apple menu in Italian, from macOS (HIToolbox.framework, Menus.loctable)
ABOUT="Informazioni su questo Mac"
SETTINGS="Impostazioni di Sistema…"
APP_STORE="App Store…"
RECENT="Elementi recenti"
APPLICATIONS="Applicazioni"
DOCUMENTS="Documenti"
SERVERS="Server"
CLEAR="Cancella menu"
FORCE_QUIT="Uscita forzata…"
SLEEP="Standby"
RESTART="Riavvia…"
SHUT_DOWN="Spegni…"
LOCK="Blocca schermo"
LOG_OUT="Esegui il logout da $(id -F)…"

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Medium 11 <text>... prints two widths. SketchyBar measures text only once it
# draws it, but the rows need a fixed width to line up the shortcuts and to highlight a whole row
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

# The badges of the Apple menu, from where it reads them: what System Settings asks attention for
# (e.g. updates) and the updates of the App Store
settings_badge() {
  plutil -extract AttentionPrefBundleIDs json -o - "$HOME/Library/Preferences/com.apple.systempreferences.plist" \
    2>/dev/null | jq '[.[]] | add // 0' 2>/dev/null || echo 0
}

app_store_badge() {
  defaults read com.apple.appstored BadgeCount 2>/dev/null || echo 0
}

# quote <text>: the text in single quotes, for the shell that runs a script
quote() {
  local quote="'\\''"
  echo "'${1//\'/$quote}'"
}

# Each render lists all the popup rows, as in claude.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are INSET from the edges, so the highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="apple.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.apple)
  sets+=(--set "$name" width=$ROW_WIDTH padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one
space() {
  row "$1" icon.drawing=off label.drawing=off background.drawing=on background.color=$TRANSPARENT \
           background.height=$2
}

# separator <name> [<indent>]: the line between groups of commands. The line is the background of
# an empty icon, as the bars in claude.sh
separator() {
  local indent=${2:-0}
  row "$1" icon.drawing=on icon="" icon.width=$((ROW_WIDTH - 2 * PADDING - indent)) \
           icon.padding_left=0 icon.padding_right=0 icon.background.drawing=on \
           icon.background.color=$SURFACE icon.background.height=1 label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.height=11
  sets+=(padding_left=$((INSET + PADDING + indent)) width=$((ROW_WIDTH - 2 * PADDING - indent)))
}

# command_row <name> <text> [<properties>...]: a command, lit up under the mouse, that runs this with
# its name on click; the properties add what is on its right
command_row() {
  local name="$1" text="$2"
  shift 2
  row "$name" icon.drawing=on icon="$text" icon.font="$FONT" icon.color=$TEXT \
              icon.padding_left=$PADDING icon.padding_right=0 icon.width=$ROW_WIDTH label.drawing=off \
              background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
              background.height=$ROW_HEIGHT script="$0 $name" "$@"
  sets+=(--subscribe "apple.$name" mouse.entered mouse.exited mouse.clicked)
}

# right <text>: sets RIGHT to the properties of the text on the right of a command, a shortcut or
# the chevron of Recent Items
right() {
  RIGHT=(icon.width=$((ROW_WIDTH - RIGHT_WIDTH - PADDING)) label.drawing=on label="$1"
         label.font="$SHORTCUT_FONT" label.color=$SUBTEXT label.width=$((RIGHT_WIDTH + PADDING))
         label.align=right label.padding_left=0 label.padding_right=$PADDING)
}

# badge <count>: sets BADGE to the properties of the badge on the right of a command, a red pill
# like the red one of the notifications, or to nothing when the count is 0
badge() {
  BADGE=()
  [ "$1" -gt 0 ] 2>/dev/null || return
  local width=$((DIGIT_WIDTH * ${#1} + 10))
  [ $width -lt $BADGE_HEIGHT ] && width=$BADGE_HEIGHT
  BADGE=(icon.width=$((ROW_WIDTH - width - PADDING)) label.drawing=on label="$1" label.font="$BADGE_FONT"
         label.color=$CRUST label.width=$width label.align=left
         label.padding_left=$(((width - DIGIT_WIDTH * ${#1}) / 2)) label.padding_right=0
         label.background.drawing=on label.background.color=$RED
         label.background.corner_radius=$((BADGE_HEIGHT / 2)) label.background.height=$BADGE_HEIGHT)
}

# recent_rows <kind> <title> <items>: the title and the items of one kind, if there are any; the
# rows are hidden until Recent Items opens
recent_rows() {
  local items
  items="$(awk -F'\t' -v kind="$1" '$1 == kind' <<< "$3")"
  [ -n "$items" ] || return
  row "recent.$1" drawing=off icon.drawing=on icon="$2" icon.font="$SMALL_FONT" icon.color=$SUBTEXT \
                  icon.padding_left=$((PADDING + INDENT)) icon.padding_right=0 label.drawing=off \
                  background.drawing=on background.color=$TRANSPARENT background.height=20
  local i=0 name target icon
  while IFS=$'\t' read -r _ name target icon; do
    row "recent.$1.$i" drawing=off icon.drawing=on icon="" \
                       icon.width=$((PADDING + INDENT + ICON_SIZE + ICON_GAP)) \
                       icon.padding_left=0 icon.padding_right=0 icon.background.drawing=on \
                       icon.background.image="$icon" icon.background.image.scale=0.25 \
                       icon.background.image.padding_left=$((PADDING + INDENT)) \
                       label.drawing=on label="$name" label.font="$FONT" label.color=$TEXT \
                       label.padding_left=0 label.padding_right=$PADDING \
                       background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
                       background.height=$ROW_HEIGHT script="$0 open $(quote "$target")"
    sets+=(--subscribe "apple.recent.$1.$i" mouse.entered mouse.exited mouse.clicked)
    i=$((i + 1))
  done <<< "$items"
}

# render_popup [<sketchybar arguments>...]: sets the popup rows, with Recent Items closed, and
# removes and adds them only when they aren't the ones already there. The arguments go in the same
# command, e.g. to open the popup
render_popup() {
  local recent settings app_store widths name names_of_recent=()
  recent="$("$HELPER" recent "$ICONS" $MAX_NAME_WIDTH)"
  settings="$(settings_badge)" app_store="$(app_store_badge)"
  while IFS=$'\t' read -r _ name _ _; do
    [ -n "$name" ] && names_of_recent+=("$name")
  done <<< "$recent"

  # The commands and what is on their right, the recent items after their icon, their titles
  widths=($(text_widths HelveticaNeue-Bold 13 "$ABOUT" "$SETTINGS" "$APP_STORE" "$RECENT" "$FORCE_QUIT" \
                                              "$SLEEP" "$RESTART" "$SHUT_DOWN" "$LOCK" "$LOG_OUT" \
                        -- SFPro-Medium 12 "⌥⌘⎋" "⌃⌘Q" "⇧⌘Q" "$CHEVRON_RIGHT" "$CHEVRON_DOWN" \
                        -- HelveticaNeue-Bold 13 "${names_of_recent[@]}" "$CLEAR" \
                        -- HelveticaNeue-Medium 11 "$APPLICATIONS" "$DOCUMENTS" "$SERVERS"))
  RIGHT_WIDTH=${widths[1]:-0}
  local badge_width=$((DIGIT_WIDTH * 2 + 10))  # up to two digits
  [ $badge_width -gt $RIGHT_WIDTH ] && RIGHT_WIDTH=$badge_width
  ROW_WIDTH=$((PADDING + ${widths[0]:-0} + GAP + RIGHT_WIDTH + PADDING))
  local recent_width=$((PADDING + INDENT + ICON_SIZE + ICON_GAP + ${widths[2]:-0} + PADDING))
  [ $recent_width -gt $ROW_WIDTH ] && ROW_WIDTH=$recent_width
  [ $((PADDING + INDENT + ${widths[3]:-0} + PADDING)) -gt $ROW_WIDTH ] &&
    ROW_WIDTH=$((PADDING + INDENT + ${widths[3]:-0} + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $ROW_WIDTH ] && ROW_WIDTH=$((MIN_WIDTH - 2 * INSET))

  space top 4
  command_row about "$ABOUT"
  separator separator.about
  badge "$settings"
  command_row settings "$SETTINGS" "${BADGE[@]}"
  badge "$app_store"
  command_row app_store "$APP_STORE" "${BADGE[@]}"
  separator separator.app_store
  right "$CHEVRON_RIGHT"
  command_row recent "$RECENT" "${RIGHT[@]}"
  recent_rows application "$APPLICATIONS" "$recent"
  recent_rows document "$DOCUMENTS" "$recent"
  recent_rows server "$SERVERS" "$recent"
  separator recent.separator $INDENT
  sets+=(drawing=off)
  if [ -n "$recent" ]; then
    command_row recent.clear "$CLEAR" drawing=off icon.padding_left=$((PADDING + INDENT))
  else
    # Nothing to clear: dimmed, like a disabled menu item
    row recent.clear drawing=off icon.drawing=on icon="$CLEAR" icon.font="$FONT" icon.color=$OVERLAY \
                     icon.padding_left=$((PADDING + INDENT)) icon.padding_right=0 label.drawing=off \
                     background.drawing=on background.color=$TRANSPARENT background.height=$ROW_HEIGHT
  fi
  separator separator.recent
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
  command_row log_out "$LOG_OUT" "${RIGHT[@]}"
  space bottom 4

  if [ "$(sketchybar --query apple | jq -r '.popup.items // [] | . - ["keep.apple"] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" "$@"
  else
    sketchybar --remove '/apple\..*/' "${adds[@]}" "${sets[@]}" "$@"
  fi
}

popup_open() {
  [ "$(sketchybar --query apple | jq -r .popup.drawing)" = on ]
}

# Recent Items opens and closes under its row, which stays under the mouse
toggle_recent() {
  if [ "$(sketchybar --query apple.recent | jq -r .label.value)" = "$CHEVRON_DOWN" ]; then
    sketchybar --set apple.recent label="$CHEVRON_RIGHT" --set '/apple\.recent\..*/' drawing=off
  else
    sketchybar --set apple.recent label="$CHEVRON_DOWN" --set '/apple\.recent\..*/' drawing=on
  fi
}

# loginwindow <event>: the Apple event the Apple menu sends to loginwindow, which shows the Force
# Quit window (apwn) or asks to confirm a restart (rrst), a shut down (rsdn) or a log out (logo)
loginwindow() {
  osascript -e "tell application \"loginwindow\" to «event aevt$1»" > /dev/null 2>&1
}

# run <command> [<target>]: as in a menu, the popup closes and then the command runs
run() {
  sketchybar --set apple popup.drawing=off
  case "$1" in
    about) open "/System/Library/CoreServices/Applications/About This Mac.app" ;;
    settings) open -b com.apple.systempreferences ;;
    app_store)
      if [ "$(app_store_badge)" -gt 0 ]; then
        open "macappstore://showUpdatesPage?scan=true"
      else
        open -b com.apple.AppStore
      fi
      ;;
    open) open "$2" ;;
    recent.clear) "$HELPER" clear ;;
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
    mouse.clicked)
      if [ "$1" = recent ]; then
        toggle_recent
      else
        run "$@"
      fi
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  mouse.clicked)
    if popup_open; then
      sketchybar --set apple popup.drawing=off
    else
      render_popup --set apple popup.drawing=on
    fi
    ;;
  mouse.exited.global) sketchybar --set apple popup.drawing=off ;;
esac
