#!/usr/bin/env bash

# Battery of the Mac: the battery item shows the charge with an icon for its state. Its popup says
# the state in words, then lists the Charge Limit of System Settings → Battery (macOS 26.4+), where
# a click on another percentage sets it, with Completa carica ora (Charge to Full Now) while the
# limit is on, the health of the battery and a row that opens the Battery settings. Completa carica
# ora pauses the limit until macOS turns it back on: the popup says so, on the percentage it goes
# back to, with a row that turns it back on now, and the percentages wait for it, dimmed.
# helpers/battery_charge reads the battery and the limit and sets the limit, which macOS has no
# command line tool for, and in watch mode triggers battery_change whenever one of them changes.
# The icon is an SF Symbol: on battery the level, yellow in Low Power Mode or else red at 20% or
# less as in the macOS battery menu, while charging the bolt, and plugged in but not charging the
# plug (an image of helpers/battery_icons.js), yellow when macOS doesn't say why. Green is a battery
# macOS looks after: the bolt while charging up to the limit, the plug while it holds the charge,
# at the limit, for Optimized Battery Charging or in the desktop mode of a Mac rarely used on battery.
# Yellow is also the bolt or the plug while Completa carica ora pauses the limit
# The item runs this with no arguments, the popup rows with limit <percent>, full or settings and
# then current or other, or with disabled

BATTERY_100=􀛨  # battery.100
BATTERY_75=􀺸   # battery.75
BATTERY_50=􀺶   # battery.50
BATTERY_25=􀛩   # battery.25
BATTERY_0=􀛪    # battery.0
CHARGING=􀢋     # battery.100.bolt
BATTERY_ICONS="$CONFIG_DIR/helpers/battery_icons"
HELPER="$CONFIG_DIR/helpers/battery_charge"

source "$CONFIG_DIR/colors.sh"

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
MIN_WIDTH=260
INSET=4           # between the rows and the edge of the popup, as in apple.sh
PADDING=8         # inside the rows
GAP=16            # between the two columns of a row
ROW_HEIGHT=24     # of a row, unless it sets its own
TITLE_HEIGHT=38   # of the title of a section, with room above
LIMITS=(80 85 90 95 100)

# The texts of the macOS battery menu where it has them
ON_BATTERY="A batteria"
CHARGING_TEXT="In carica"
FULL="Carica completa"
ON_HOLD="Carica sospesa"
NOT_CHARGING="La batteria non è in carica"
LIMIT_TITLE="Limite di carica"
NO_LIMIT="Nessun limite"
CHARGE_TO_FULL="Completa carica ora"
PAUSED="Sospeso"
PAUSED_DETAILS="Per Completa carica ora: macOS lo riattiva da solo più tardi"
RESUME="Riattiva il limite ora"
FAILED="Non riuscito"
HEALTH_TITLE="Stato batteria"
NORMAL="Normale"
SERVICE="Assistenza consigliata"
SETTINGS="Impostazioni Batteria…"

# image_or <png> <symbol>: the image, or the SF Symbol when sketchybarrc couldn't make it
image_or() {
  if [ -f "$1" ]; then echo "$1"; else echo "$2"; fi
}

# level <percentage>: the icon of the closest level
level() {
  if [ "$1" -ge 88 ]; then echo $BATTERY_100
  elif [ "$1" -ge 63 ]; then echo $BATTERY_75
  elif [ "$1" -ge 38 ]; then echo $BATTERY_50
  elif [ "$1" -ge 13 ]; then echo $BATTERY_25
  else echo $BATTERY_0
  fi
}

# icon_settings <icon>: sets ICON_SETTINGS to the icon settings of the item, for an SF Symbol or an
# image, as in audio.sh. The images are drawn at 4 px per point, hence the scale. An image ignores
# the padding of the icon and starts at its left edge: image.padding_left leaves the same space as
# before the symbols (icon.padding_left plus their origin), in an icon as wide as that and the
# image, whose width in px is in the PNG header. icon.width=dynamic undoes it
icon_settings() {
  case "$1" in
    /*)
      local a b c d
      read -r a b c d < <(od -An -tu1 -j16 -N4 "$1")
      ICON_SETTINGS=(icon="" icon.width=$((12 + ((a << 24 | b << 16 | c << 8 | d) + 3) / 4))
                     icon.background.drawing=on icon.background.image="$1"
                     icon.background.image.scale=0.25 icon.background.image.padding_left=12)
      ;;
    *) ICON_SETTINGS=(icon="$1" icon.width=dynamic icon.background.drawing=off) ;;
  esac
}

# duration <minutes>: e.g. 2 h 57 min
duration() {
  if [ "$1" -ge 60 ]; then echo "$(($1 / 60)) h $(($1 % 60)) min"; else echo "$1 min"; fi
}

# The battery as helpers/battery_charge reports it, then state: ICON and COLOR for the bar, and
# STATUS, STATUS_COLOR and DETAILS for the popup
read_battery() {
  IFS=$'\t' read -r PERCENT POWER IS_CHARGING CHARGED MINUTES LIMIT LIMIT_STATE HELD DESKTOP LOW_POWER WATTS \
    < <("$HELPER" status 2>/dev/null)
}

state() {
  STATUS_COLOR=$TEXT DETAILS=""
  if [ "$POWER" = battery ]; then
    ICON=$(level "$PERCENT") COLOR=$TEXT STATUS=$ON_BATTERY
    if [ "$LOW_POWER" = 1 ]; then
      COLOR=$YELLOW
    elif [ "$PERCENT" -le 20 ]; then
      COLOR=$RED
    fi
    if [ "$MINUTES" -gt 0 ]; then DETAILS="Ancora $(duration "$MINUTES")"; else DETAILS="Calcolo del tempo rimanente…"; fi
    [ "$LOW_POWER" = 1 ] && DETAILS="$DETAILS · risparmio energetico"
    return
  fi

  if [ "$IS_CHARGING" = 1 ]; then
    ICON=$CHARGING COLOR=$TEXT STATUS=$CHARGING_TEXT
    case "$LIMIT_STATE" in
      on) COLOR=$GREEN DETAILS="Fino al limite ($LIMIT%)" ;;
      paused) COLOR=$YELLOW DETAILS="Fino al 100%" ;;
      *) [ "$MINUTES" -gt 0 ] && DETAILS="Completa tra $(duration "$MINUTES")" ;;
    esac
  else
    # Apple: the Mac stops within a few percent of the limit and charges again once it is 5% below
    if [ "$CHARGED" = 1 ] || [ "$PERCENT" -ge 100 ]; then
      COLOR=$TEXT STATUS=$FULL
    elif [ "$LIMIT_STATE" = on ] && [ "$PERCENT" -ge $((LIMIT - 5)) ]; then
      COLOR=$GREEN STATUS="Ferma al limite ($LIMIT%)"
    elif [ "$HELD" = 1 ]; then
      COLOR=$GREEN STATUS=$ON_HOLD DETAILS="Caricamento ottimizzato"
      [ "$DESKTOP" = 1 ] && DETAILS="Modalità desktop"
    else
      COLOR=$YELLOW STATUS=$NOT_CHARGING STATUS_COLOR=$YELLOW
    fi
    [ "$LIMIT_STATE" = paused ] && COLOR=$YELLOW
    local name=text
    [ "$COLOR" = $GREEN ] && name=green
    [ "$COLOR" = $YELLOW ] && name=yellow
    ICON=$(image_or "$BATTERY_ICONS/plug_$name.png" "$(level "$PERCENT")")
  fi
  [ -n "$WATTS" ] && DETAILS="${DETAILS:+$DETAILS · }alimentatore da $WATTS W"
  # The first letter of the details in upper case
  DETAILS="$(tr '[:lower:]' '[:upper:]' <<< "${DETAILS:0:1}")${DETAILS:1}"
}

# "<condition>\t<maximum capacity>\t<cycles>" of the battery, as in System Settings
health() {
  system_profiler SPPowerDataType -json 2>/dev/null |
    jq -r '.SPPowerDataType[].sppower_battery_health_info // empty
           | [.sppower_battery_health // "", .sppower_battery_health_maximum_capacity // "",
              .sppower_battery_cycle_count // ""] | @tsv'
}

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Medium 11 <text>... prints two widths, as in audio.sh. SketchyBar measures text
# only once it draws it, but the rows need a fixed width to line up the right column and to
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
# The rows are always the same, the ones not needed hidden: removing the row under the mouse, e.g.
# Completa carica ora once clicked, would close the popup (mouse.exited.global). The rows are INSET
# from the edges, so the highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="battery.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.battery)
  sets+=(--set "$name" padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# text_row <name> <left> <left font> <left color> [<right> <right font> <right color>]: a row with
# a text on the left and, if given, one on the right. The rows that need more room above or less
# add background.height
text_row() {
  local properties=(drawing=on width=$WIDTH icon.drawing=on icon="$2" icon.font="$3" icon.color=$4
                    icon.padding_left=$PADDING icon.padding_right=0 label.padding_left=0
                    background.drawing=on background.color=$TRANSPARENT background.height=$ROW_HEIGHT)
  if [ -n "$5" ]; then
    # A fixed width includes the padding
    properties+=(icon.width=$((WIDTH - RIGHT_WIDTH - PADDING))
                 label.drawing=on label="$5" label.font="$6" label.color=$7 label.width=$((RIGHT_WIDTH + PADDING))
                 label.align=right label.padding_right=$PADDING)
  else
    properties+=(icon.width=dynamic label.drawing=off)
  fi
  row "$1" "${properties[@]}"
}

# button_row <name> <text> <color> <action> <current|other> [disabled]: lit up under the mouse, and
# on a background when it is the current one; a click runs this with the action. Disabled, it is
# dimmed and ignores the mouse, still on its background when it is the current one
button_row() {
  local background=$TRANSPARENT color=$3 script="$0 $4 $5"
  [ "$5" = current ] && background=$SURFACE
  [ "$6" = disabled ] && color=$OVERLAY script="$0 disabled"
  row "$1" drawing=on width=$WIDTH icon.drawing=on icon="$2" icon.font="$FONT" icon.color=$color \
           icon.padding_left=$PADDING icon.padding_right=0 icon.width=dynamic label.drawing=off \
           background.drawing=on background.color=$background background.corner_radius=6 \
           background.height=$ROW_HEIGHT script="$script"
  sets+=(--subscribe "battery.row.$1" mouse.entered mouse.exited mouse.clicked)
}

render_popup() {
  local condition capacity cycles condition_text="" condition_color=$SUBTEXT health_details="" option
  IFS=$'\t' read -r condition capacity cycles <<< "$(health)"
  if [ -n "$condition" ]; then
    condition_text=$NORMAL
    [ "$condition" = Good ] || condition_text=$SERVICE condition_color=$YELLOW
    health_details="Capacità massima $capacity · $cycles cicli"
  fi

  local options=()
  for option in "${LIMITS[@]}"; do options+=("$option%"); done
  local widths
  widths=($(text_widths HelveticaNeue-Bold 13 "$STATUS" "$LIMIT_TITLE" "${options[@]}" "$NO_LIMIT" \
                        "$CHARGE_TO_FULL" "$RESUME" "$FAILED" "$HEALTH_TITLE" "$SETTINGS" \
                        -- HelveticaNeue-Bold 13 "100%" "$PAUSED" "$condition_text" \
                        -- HelveticaNeue-Medium 11 "$DETAILS" "$PAUSED_DETAILS" "$health_details"))
  RIGHT_WIDTH=${widths[1]:-0}
  WIDTH=$((PADDING + ${widths[0]:-0} + GAP + RIGHT_WIDTH + PADDING))
  [ $((PADDING + ${widths[2]:-0} + PADDING)) -gt $WIDTH ] && WIDTH=$((PADDING + ${widths[2]:-0} + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))

  space top 4
  text_row status "$STATUS" "$FONT" $STATUS_COLOR "$PERCENT%" "$FONT" $COLOR
  # Close to the state, as in claude.sh
  text_row details "$DETAILS" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=16)
  [ -n "$DETAILS" ] || sets+=(drawing=off)

  # The limit: the current percentage on a background. While Completa carica ora pauses it, the
  # title says so, the percentage on a background is the one it goes back to and the row in place
  # of Completa carica ora turns it back on now: until then the percentages are disabled, since a
  # click on one would turn it back on too, at another percentage. Without that row, when this
  # helper never saw the limit on, they are the way to turn it back on
  if [ "$LIMIT_STATE" = paused ]; then
    text_row limit "$LIMIT_TITLE" "$FONT" $TEXT "$PAUSED" "$FONT" $YELLOW
  else
    text_row limit "$LIMIT_TITLE" "$FONT" $TEXT
  fi
  sets+=(background.height=$TITLE_HEIGHT)
  [ "$LIMIT_STATE" = none ] && sets+=(drawing=off)
  text_row limit.details "$PAUSED_DETAILS" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=16)
  [ "$LIMIT_STATE" = paused ] || sets+=(drawing=off)
  local current text disabled=""
  [ "$LIMIT_STATE" = paused ] && [ "$LIMIT" -gt 0 ] && disabled=disabled
  for option in "${LIMITS[@]}"; do
    current=other text="$option%"
    [ "$option" = "$LIMIT" ] && current=current
    [ "$option" = 100 ] && text=$NO_LIMIT
    button_row "limit.$option" "$text" $TEXT "limit $option" $current $disabled
    [ "$LIMIT_STATE" = none ] && sets+=(drawing=off)
  done
  if [ "$LIMIT_STATE" = paused ]; then
    button_row full "$RESUME" $PRIMARY "limit $LIMIT" other
    # Without the limit it goes back to, which this helper never saw on, nothing to turn back on
    [ "$LIMIT" -gt 0 ] || sets+=(drawing=off)
  else
    button_row full "$CHARGE_TO_FULL" $PRIMARY full other
    [ "$LIMIT_STATE" = on ] && [ "$POWER" = ac ] && [ "$PERCENT" -lt 100 ] || sets+=(drawing=off)
  fi

  text_row health "$HEALTH_TITLE" "$FONT" $TEXT "$condition_text" "$FONT" $condition_color
  sets+=(background.height=$TITLE_HEIGHT)
  [ -n "$condition" ] || sets+=(drawing=off)
  text_row health.details "$health_details" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=16)
  [ -n "$condition" ] || sets+=(drawing=off)

  # Apart from the battery
  text_row settings.gap "" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=10)
  button_row settings "$SETTINGS" $PRIMARY settings other
  space bottom 4

  if [ "$(sketchybar --query battery | jq -r '.popup.items // [] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}"
  else
    sketchybar --remove '/battery\.row\..*/' "${adds[@]}" "${sets[@]}"
  fi
}

# update [popup]: the bar item and, while it is open or when asked, the popup; hidden without a
# battery, e.g. on a Mac desktop
update() {
  read_battery
  if [ -z "$PERCENT" ]; then
    sketchybar --set battery drawing=off popup.drawing=off
    return
  fi
  state
  icon_settings "$ICON"
  sketchybar --set battery drawing=on "${ICON_SETTINGS[@]}" icon.color=$COLOR label="$PERCENT%"
  if [ "$1" = popup ] || [ "$(sketchybar --query battery | jq -r .popup.drawing)" = on ]; then
    render_popup
  fi
}

# A popup row: a limit, Completa carica ora or the Battery settings, or a disabled one
case "$1" in
  disabled) exit 0 ;;
  limit | full | settings)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited)
        if [ "${!#}" = current ]; then
          sketchybar --set "$NAME" background.color=$SURFACE
        else
          sketchybar --set "$NAME" background.color=$TRANSPARENT
        fi
        ;;
      # Until the popup is set again the row says when macOS refused, e.g. to turn the limit back on
      mouse.clicked)
        failed=""
        case "$1" in
          limit) "$HELPER" limit "$2" || failed=1 ;;
          full) "$HELPER" full || failed=1 ;;
          settings)
            sketchybar --set battery popup.drawing=off
            open "x-apple.systempreferences:com.apple.Battery-Settings.extension"
            exit 0
            ;;
        esac
        update popup
        [ -n "$failed" ] && sketchybar --set "$NAME" icon="$FAILED" icon.color=$RED
        ;;
    esac
    exit 0
    ;;
esac

case "$SENDER" in
  mouse.clicked)
    if [ "$(sketchybar --query battery | jq -r .popup.drawing)" = on ]; then
      sketchybar --set battery popup.drawing=off
    else
      sketchybar --set battery popup.drawing=on
      update popup
    fi
    ;;
  mouse.exited.global) sketchybar --set battery popup.drawing=off ;;
  # battery_change from helpers/battery_charge, power_source_change, system_woke and the first run
  *) update ;;
esac
