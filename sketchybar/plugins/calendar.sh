#!/usr/bin/env bash

# Next event of the day from the macOS calendars, or today's all-day events once there are no more
# timed ones. helpers/calendar_events sends it with calendar_change (KIND, TIME, MINUTES and LABEL,
# already in the language of the Mac), with all the events of the day (EVENTS) for the popup when
# they change, not at each minute of the countdowns of the label. calendar_time shows the icon and
# the time the event starts, white, then yellow, orange and red as it comes closer, and in the color
# of the event in progress in the popup while it is on; calendar_title the rest of the label, but not
# on the display with the notch (see notch.sh). A click on either opens the popup of the calendar
# bracket, the past events dimmed and the one in progress highlighted; a click on an event joins its
# Google Meet call, shown by the Meet logo of helpers/meet_icon.png, or else shows it in Calendar
# calendar_time and calendar_title run this with no arguments, each popup row with the link it opens
# The icon is an SF Symbol, so it needs the SF Pro font (brew install --cask font-sf-pro)

CALENDAR=􀉉  # calendar
MEET_ICON="$CONFIG_DIR/helpers/meet_icon.png"

source "$CONFIG_DIR/colors.sh"

SOON=30      # minutes before the event from which its time turns yellow
SOONER=15    # orange
IMMINENT=5   # and red

# calendar_title follows the padding after the label of calendar_time, label.padding_right +
# padding_right (10): its padding_left leaves two spaces after the time (7) or, after an empty
# label, only the room after the icon, as in the other items (icon.padding_right + label.padding_left)
TITLE_AFTER_TIME=-3
TITLE_AFTER_ICON=-10

FONT="Helvetica Neue:Bold:13.0"  # the default label font
MIN_WIDTH=220
INSET=4       # between the rows and the edge of the popup, as in apple.sh
PADDING=8     # inside the rows
GAP=16        # between the time and the title, and before the Meet logo
LOGO=16       # the Meet logo, a square that helpers/meet_icon.js draws at 4 px per point
ROW_HEIGHT=24

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Bold 13 <text>... prints two widths, as in apple.sh. SketchyBar measures text only
# once it draws it, but the rows need a fixed width to line up the titles and the logos and to
# highlight a whole row
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

# Each render lists all the popup rows, as in claude.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are INSET from the edges, so the highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="calendar.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.calendar)
  sets+=(--set "$name" width=$ROW_WIDTH padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one
space() {
  row "$1" icon.drawing=off label.drawing=off background.drawing=on background.color=$TRANSPARENT \
           background.height=$2 background.image.drawing=off
}

# render [<sketchybar arguments>...]: the popup rows from EVENTS, a line for each event with its
# fields separated by \x1f: allday, past, ongoing or upcoming, the time, the title, the Meet call
# and the link to Calendar. It removes and adds the rows only when they aren't the ones already
# there: the popup may be open, and removing the row under the mouse would close it. The arguments
# go in the same command
render() {
  local states=() times=() titles=() meets=() links=() state time title meet link
  while IFS=$'\x1f' read -r state time title meet link; do
    [ -n "$state" ] || continue
    states+=("$state") times+=("$time") titles+=("$title") meets+=("$meet") links+=("${meet:-$link}")
  done <<< "$EVENTS"

  if [ ${#states[@]} -eq 0 ]; then
    sketchybar --remove '/calendar\.row\..*/' --set calendar popup.drawing=off "$@"
    return
  fi

  # The time, then the title, then the logo if any event has one, which lines them all up
  local widths time_width logo_width=0
  widths=($(text_widths HelveticaNeue-Bold 13 "${times[@]}" -- HelveticaNeue-Bold 13 "${titles[@]}"))
  time_width=$((PADDING + ${widths[0]} + GAP))
  [ -f "$MEET_ICON" ] && [ -n "$(printf "%s" "${meets[@]}")" ] && logo_width=$((GAP + LOGO))
  ROW_WIDTH=$((time_width + ${widths[1]} + logo_width + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $ROW_WIDTH ] && ROW_WIDTH=$((MIN_WIDTH - 2 * INSET))

  space top 4
  local i colors logo
  for ((i = 0; i < ${#states[@]}; i++)); do
    case "${states[i]}" in
      past) colors=($OVERLAY $OVERLAY) ;;
      ongoing) colors=($PRIMARY $TEXT) ;;
      *) colors=($SUBTEXT $TEXT) ;;
    esac
    # The logo is the background image of the row, from its left edge
    logo=(background.image.drawing=off)
    [ $logo_width -gt 0 ] && [ -n "${meets[i]}" ] &&
      logo=(background.image="$MEET_ICON" background.image.drawing=on background.image.scale=0.25
            background.image.padding_left=$((ROW_WIDTH - PADDING - LOGO)))
    # The links have no characters that need quoting (see helpers/calendar_events.swift) but the &
    # of those to Calendar, which the single quotes keep from the shell
    row "event.$i" icon.drawing=on icon="${times[i]}" icon.font="$FONT" icon.color=${colors[0]} \
                   icon.padding_left=$PADDING icon.padding_right=0 icon.width=$time_width \
                   label.drawing=on label="${titles[i]}" label.font="$FONT" label.color=${colors[1]} \
                   label.padding_left=0 label.padding_right=$PADDING \
                   background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
                   background.height=$ROW_HEIGHT "${logo[@]}" script="$0 '${links[i]}'"
    sets+=(--subscribe "calendar.row.event.$i" mouse.entered mouse.exited mouse.clicked)
  done
  space bottom 4

  if [ "$(sketchybar --query calendar | jq -r '.popup.items // [] | . - ["keep.calendar"] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" "$@"
  else
    sketchybar --remove '/calendar\.row\..*/' "${adds[@]}" "${sets[@]}" "$@"
  fi
}

# time_color: the color of the icon and the time of the event
time_color() {
  if [ "$KIND" = ongoing ]; then
    echo $PRIMARY
  elif [ "$MINUTES" -le $IMMINENT ]; then
    echo $RED
  elif [ "$MINUTES" -le $SOONER ]; then
    echo $PEACH
  elif [ "$MINUTES" -le $SOON ]; then
    echo $YELLOW
  else
    echo $TEXT
  fi
}

# A popup row: as in a menu, the popup closes and then the link opens
if [[ $NAME == calendar.row.* ]]; then
  case "$SENDER" in
    mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked)
      sketchybar --set calendar popup.drawing=off
      open "$1"
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  # Only calendar_change carries the events: the forced update at startup has nothing to show.
  # Without a time the label of calendar_time is empty, not hidden: its padding is the room after
  # the icon, as in claude.sh
  calendar_change)
    case "$KIND" in
      upcoming | ongoing)
        color=$(time_color)
        items=(--set calendar.gap drawing=on
               --set calendar_time drawing=on icon.color=$color label="$TIME" label.color=$color
               --set calendar_title drawing=on label="$LABEL" label.color=$TEXT padding_left=$TITLE_AFTER_TIME)
        ;;
      allday | denied)
        color=$TEXT
        [ "$KIND" = denied ] && color=$RED
        items=(--set calendar.gap drawing=on --set calendar_time drawing=on icon.color=$color label=""
               --set calendar_title drawing=on label="$LABEL" label.color=$color padding_left=$TITLE_AFTER_ICON)
        ;;
      *) items=(--set calendar.gap drawing=off --set calendar_time drawing=off --set calendar_title drawing=off
                --set calendar popup.drawing=off) ;;
    esac
    if [ -n "${EVENTS+set}" ]; then
      render --set calendar_time icon="$CALENDAR" "${items[@]}"
    else
      sketchybar --set calendar_time icon="$CALENDAR" "${items[@]}"
    fi
    ;;
  # Without access to the calendars there are no events: the click opens Calendar
  mouse.clicked)
    if [ "$(sketchybar --query calendar | jq '.popup.items // [] | . - ["keep.calendar"] | length')" -gt 0 ]; then
      sketchybar --set calendar popup.drawing=toggle
    else
      open -a Calendar
    fi
    ;;
  mouse.exited.global) sketchybar --set calendar popup.drawing=off ;;
esac
