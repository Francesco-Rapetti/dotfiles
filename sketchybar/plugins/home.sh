#!/usr/bin/env bash

# Home Assistant: the home item shows its logo and how many devices of the popup are on, gray while Home
# Assistant can't be reached, and the home_printer item on its left the progress of the 3D printer,
# if there is one, while it prints, in yellow while paused. A click on either opens the popup of home: the devices
# in groups, each with its state on the right, where a click turns on or off the lights, the plugs
# and the climate, opens or closes the blinds, sends the vacuum to clean or back to its base, or
# runs the script. A slider under the dimmable lights, the blinds and the climate that is on sets
# the brightness, the position or the temperature when released; the climate that is on also has
# its mode under it, where a click lists the others to switch to. The plug of the printer asks for
# a second click to turn off, and turns off through a script of Home Assistant that does nothing
# while the printer works; while it prints, a bar under it has the progress and the time left. The
# last row opens the dashboard.
# helpers/home_assistant follows the entities through the WebSocket API of Home Assistant, keeps
# their state in CACHE and triggers home_assistant_change when it changes; it also calls the
# services, with the token in the keychain. The icons are SF Symbols that
# helpers/home_assistant_icons.js draws into helpers/home_assistant_icons in the colors of
# colors.sh: SketchyBar can't color images, and in the rows the icon comes before the name, so it
# has to be an image, as in audio.sh
# The items run this with no arguments, sketchybarrc with watch, which starts the helper, the rows
# of the popup with row <entity>, the sliders with slider <entity>, the mode of a climate with
# modes <entity> and the modes it lists with mode <entity> <mode>, or with current for the one it
# is in, and the last row with dashboard

source "$CONFIG_DIR/colors.sh"

# SERVER, DASHBOARD, the ROWS of the popup and the PRINTER_ entities: home_assistant.conf isn't in
# the repo, home_assistant.conf.example says what goes in it. Without it the items stay hidden
CONF="$CONFIG_DIR/home_assistant.conf"
if [ ! -f "$CONF" ]; then
  [ "$1" = watch ] || sketchybar --set home drawing=off --set home_printer drawing=off
  exit 0
fi
source "$CONF"

HELPER="$CONFIG_DIR/helpers/home_assistant"
ICONS="$CONFIG_DIR/helpers/home_assistant_icons"
CACHE="${TMPDIR:-/tmp}/sketchybar_home_assistant.json"
MODES_FILE="${TMPDIR:-/tmp}/sketchybar_home_modes"  # the climate whose modes the popup lists

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
MIN_WIDTH=260
INSET=4            # between the rows and the edge of the popup, as in apple.sh
PADDING=8          # inside the rows
GAP=8              # between the icon and the name of a device
COLUMN_GAP=16      # between the name of a device and its state
ICON_WIDTH=21      # the column of the icons, as wide as the widest, the plug
ROW_HEIGHT=26      # of a device
SLIDER_HEIGHT=8
BAR_HEIGHT=6
MAX_MODES=6        # of a climate besides off: all those of Home Assistant
KNOB=􀀁  # circle.fill

ON="Accesa"
OFF="Spenta"
CLIMATE_OFF="Spento"
MODES_TITLE="Modalità"
HEAT="Caldo"
COOL="Freddo"
DRY="Deumidifica"
FAN_ONLY="Ventola"
HEAT_COOL="Caldo/freddo"
AUTO="Automatico"
OPEN="Aperta"
CLOSED="Chiusa"
OPENING="Si apre…"
CLOSING="Si chiude…"
CLEANING="Pulisce"
RETURNING="Torna alla base"
DOCKED="Alla base"
PAUSED="In pausa"
IDLE="Fermo"
ERROR="Errore"
RUN="Avvia"
RUNNING="In corso…"
PRINTING="In stampa"
PREPARING="Si prepara a stampare…"
CONFIRM_OFF="Fai clic per spegnere"
TURNING_OFF="Spegnimento…"
FAILED="Non riuscito"
UNAVAILABLE="Non disponibile"
UNREACHABLE="Home Assistant non raggiungibile"
OPEN_DASHBOARD="Apri Home Assistant"

# The entities of the rows and their names, by index
ENTITIES=() NAMES=()
for ((i = 0; i < ${#ROWS[@]}; i += 2)); do
  [ "${ROWS[i]}" = group ] && continue
  ENTITIES+=("${ROWS[i]}")
  NAMES+=("${ROWS[i + 1]}")
done

# read_states: from CACHE, ONLINE, true while the helper is connected to Home Assistant, and for
# each entity of ENTITIES, by index, STATES and FIELDS: the state, the brightness of a light in %
# (empty when off), whether it can dim, the position of a blind in %, the temperature and target of
# the climate as text, e.g. 25,5°, the target in % of its range, for the slider, and the modes of
# the climate, separated by spaces; separated by \x1f since they can be empty. Then PRINTER: the
# status of the printer, its progress and the minutes left
read_states() {
  local lines=() line i
  while IFS= read -r line; do
    lines+=("$line")
  done < <(jq -r --arg status "$PRINTER_STATUS" --arg progress "$PRINTER_PROGRESS" \
              --arg remaining "$PRINTER_REMAINING" '
    def degrees: if type == "number" then ((. * 10 | round) / 10 | tostring | sub("\\."; ",")) + "°" else "" end;
    .states as $s
    | (.online | tostring),
      ($ARGS.positional[] | ($s[.] // {state: "unavailable", attributes: {}}) as {state: $state, attributes: $a}
       | [$state,
          (if $a.brightness then $a.brightness / 2.55 | round else "" end),
          (($a.supported_color_modes // []) - ["onoff"] | length > 0),
          ($a.current_position // "" | if . == "" then . else round end),
          ($a.current_temperature | degrees),
          ($a.temperature | degrees),
          (if ($a.temperature | type) == "number" and ($a.max_temp // 0) > ($a.min_temp // 0)
           then ($a.temperature - $a.min_temp) / ($a.max_temp - $a.min_temp) * 100 | round else "" end),
          ($a.hvac_modes // [] | join(" "))]
       | map(tostring) | join("\u001f")),
      ([$s[$status].state // "",
        ($s[$progress].state | tonumber? | round) // "",
        ($s[$remaining].state | tonumber? | . * 60 | round) // ""] | map(tostring) | join("\u001f"))
    ' --args "${ENTITIES[@]}" 2>/dev/null < "$CACHE")
  ONLINE=${lines[0]}
  STATES=() FIELDS=()
  for ((i = 0; i < ${#ENTITIES[@]}; i++)); do
    FIELDS+=("${lines[i + 1]}")
    STATES+=("${lines[i + 1]%%$'\x1f'*}")
  done
  PRINTER=${lines[${#ENTITIES[@]} + 1]}
}

# printing <status>: whether the printer is working on a print, also while paused
printing() {
  case "$1" in
    running | pause | prepare | slicing) return 0 ;;
    *) return 1 ;;
  esac
}

# png_width <png>: in points, from the width in px in the PNG header, 4 px per point
png_width() {
  local a b c d
  read -r a b c d < <(od -An -tu1 -j16 -N4 "$1")
  echo $((((a << 24 | b << 16 | c << 8 | d) + 3) / 4))
}

# bar_icon <png>: sets ICON to the icon settings of a bar item for an image, as for the claude item:
# an image ignores the padding of the icon and starts at its left edge, so image.padding_left
# leaves the room before the symbols of the other items (icon.padding_left plus their origin), in
# an icon as wide as that and the image
bar_icon() {
  ICON=(icon="" icon.width=$((12 + $(png_width "$1"))) icon.background.drawing=on
        icon.background.image="$1" icon.background.image.scale=0.25 icon.background.image.padding_left=12)
}

# update_bar: the logo of Home Assistant in its blue, gray while Home Assistant can't be reached, or
# a house without the logo (see sketchybarrc), with how many devices are on; the printer with its
# progress while it prints
update_bar() {
  local on=0 i label="" logo=overlay house=overlay status progress printer=(drawing=off)
  if [ "$ONLINE" = true ]; then
    logo=brand house=text
    for ((i = 0; i < ${#ENTITIES[@]}; i++)); do
      case "${ENTITIES[i]%%.*}:${STATES[i]}" in
        light:on | switch:on | vacuum:cleaning) on=$((on + 1)) ;;
        climate:off | climate:unavailable | climate:unknown) ;;
        climate:*) on=$((on + 1)) ;;
      esac
    done
    [ $on -gt 0 ] && label=$on
    IFS=$'\x1f' read -r status progress _ <<< "$PRINTER"
    if printing "$status"; then
      local color=text label_color=$TEXT
      [ "$status" = pause ] && color=yellow label_color=$YELLOW
      bar_icon "$ICONS/printer.fill_$color.png"
      printer=(drawing=on "${ICON[@]}" label="${progress:-0}%" label.color=$label_color)
    fi
  fi
  if [ -f "$ICONS/logo_$logo.png" ]; then
    bar_icon "$ICONS/logo_$logo.png"
  else
    bar_icon "$ICONS/house.fill_$house.png"
  fi
  sketchybar --set home "${ICON[@]}" label="$label" --set home_printer "${printer[@]}"
}

# mode_look <hvac mode>: sets SYMBOL and COLOR, the icon of a climate in that mode, and MODE, its
# name
mode_look() {
  case "$1" in
    off) SYMBOL=thermometer.medium COLOR=subtext MODE=$CLIMATE_OFF ;;
    heat) SYMBOL=flame.fill COLOR=peach MODE=$HEAT ;;
    cool) SYMBOL=snowflake COLOR=sky MODE=$COOL ;;
    dry) SYMBOL=humidity.fill COLOR=teal MODE=$DRY ;;
    fan_only) SYMBOL=fan.fill COLOR=teal MODE=$FAN_ONLY ;;
    heat_cool) SYMBOL=thermometer.medium COLOR=text MODE=$HEAT_COOL ;;
    auto) SYMBOL=thermometer.medium COLOR=text MODE=$AUTO ;;
    *) SYMBOL=thermometer.medium COLOR=text MODE=$1 ;;
  esac
}

# device <index>: the look of the row of the entity: SYMBOL in COLOR, the names of the images of
# helpers/home_assistant_icons.js and sketchybarrc, the name in NAME_COLOR, LABEL on the right in
# LABEL_COLOR, SLIDER, the percentage of its slider, empty when it has none or it is hidden, and
# HVAC, the modes of a climate
device() {
  local entity=${ENTITIES[$1]} name=${NAMES[$1]} state brightness dimmable position temperature target percent
  IFS=$'\x1f' read -r state brightness dimmable position temperature target percent HVAC <<< "${FIELDS[$1]}"
  NAME_COLOR=$TEXT LABEL_COLOR=$TEXT SLIDER=""
  case "${entity%%.*}" in
    light | switch)
      SYMBOL=lightbulb.fill COLOR=yellow LABEL=$ON
      if [ "$entity" = "$PRINTER_PLUG" ]; then
        SYMBOL=printer.fill
      elif [ "${entity%%.*}" = switch ] && [ "${name#Luce}" = "$name" ]; then
        SYMBOL=powerplug.fill
      fi
      if [ "$state" = on ]; then
        [ "$dimmable" = true ] && LABEL="${brightness:-0}%"
        [ "$entity" = "$PRINTER_PLUG" ] && printing "${PRINTER%%$'\x1f'*}" && LABEL=$PRINTING
      else
        [ $SYMBOL = lightbulb.fill ] && SYMBOL=lightbulb
        COLOR=subtext LABEL=$OFF LABEL_COLOR=$SUBTEXT
      fi
      [ "$dimmable" = true ] && SLIDER=${brightness:-0}
      ;;
    cover)
      SYMBOL=roller.shade.open COLOR=text LABEL=$OPEN SLIDER=${position:-0}
      case "$state" in
        opening) LABEL=$OPENING ;;
        closing) LABEL=$CLOSING ;;
        closed) SYMBOL=roller.shade.closed COLOR=subtext LABEL=$CLOSED LABEL_COLOR=$SUBTEXT ;;
        *) [ -n "$position" ] && [ "$position" -lt 100 ] && LABEL="$position%" ;;
      esac
      ;;
    climate)
      mode_look "$state"
      if [ "$state" = off ]; then
        LABEL="$CLIMATE_OFF${temperature:+ · $temperature}" LABEL_COLOR=$SUBTEXT
      else
        LABEL=$temperature
        [ -n "$target" ] && LABEL="${temperature:+$temperature → }$target" SLIDER=$percent
      fi
      ;;
    vacuum)
      SYMBOL=robotic.vacuum.fill COLOR=subtext LABEL_COLOR=$SUBTEXT
      case "$state" in
        cleaning) COLOR=green LABEL=$CLEANING LABEL_COLOR=$TEXT ;;
        returning) COLOR=text LABEL=$RETURNING LABEL_COLOR=$TEXT ;;
        docked) LABEL=$DOCKED ;;
        paused) LABEL=$PAUSED ;;
        error) COLOR=red LABEL=$ERROR LABEL_COLOR=$RED ;;
        *) LABEL=$IDLE ;;
      esac
      ;;
    *)
      # script and scene
      SYMBOL=play.fill COLOR=primary LABEL=$RUN LABEL_COLOR=$PRIMARY
      [ "$state" = on ] && LABEL=$RUNNING LABEL_COLOR=$YELLOW
      ;;
  esac
  [ "$state" = unavailable ] && COLOR=overlay NAME_COLOR=$OVERLAY LABEL=$UNAVAILABLE LABEL_COLOR=$OVERLAY SLIDER=""
}

# left <minutes>: e.g. 1 h 20 min
left() {
  if [ "$1" -ge 60 ]; then
    echo "$(($1 / 60)) h $(($1 % 60)) min"
  else
    echo "$1 min"
  fi
}

# printer_text: the line under the bar of the printer, e.g. 45% · ancora 1 h 20 min
printer_text() {
  local status progress minutes
  IFS=$'\x1f' read -r status progress minutes <<< "$PRINTER"
  case "$status" in
    prepare | slicing) echo "$PREPARING" ;;
    pause) echo "$PAUSED · ${progress:-0}%" ;;
    *) echo "${progress:-0}%${minutes:+ · ancora $(left "$minutes")}" ;;
  esac
}

# Width in points of the widest text of each group, e.g. text_widths HelveticaNeue-Bold 13 <text>...
# -- HelveticaNeue-Medium 11 <text>... prints two widths. SketchyBar measures text only once it
# draws it, but the rows need a fixed width to line up the states and to highlight a whole row
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

# Each render lists all the popup rows, as in audio.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are always the same, those not needed hidden, as in system.sh: removing the row under
# the mouse would close the popup (mouse.exited.global). The rows are INSET from the edges, so the
# highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="home.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.home)
  sets+=(--set "$name" drawing=on padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room below the last row, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# text_row <name> <height> <text> <font> <color>
text_row() {
  row "$1" width=$WIDTH icon.drawing=on icon="$3" icon.font="$4" icon.color=$5 \
           icon.padding_left=$PADDING icon.padding_right=0 icon.width=dynamic label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.height=$2
}

# device_row <index>: the icon, centered in a column ICON_WIDTH wide after the padding, then the
# name, both in the icon, and the state, the label; it lights up under the mouse. SketchyBar draws
# only an icon and a label in a row, hence the image in the background of the icon, as in audio.sh.
# HOVER is empty but on the first render: setting the background color again would turn off the
# highlight of the row under the mouse, e.g. the one just clicked
device_row() {
  local image="$ICONS/${SYMBOLS[$1]}_${COLORS[$1]}.png"
  row "row.$1" width=$WIDTH \
               icon.drawing=on icon="${NAMES[$1]}" icon.font="$FONT" icon.color=${NAME_COLORS[$1]} icon.align=left \
               icon.padding_left=$((PADDING + ICON_WIDTH + GAP)) icon.padding_right=0 \
               icon.width=$((WIDTH - RIGHT_WIDTH - PADDING)) \
               icon.background.drawing=on icon.background.image="$image" icon.background.image.scale=0.25 \
               icon.background.image.padding_left=$((PADDING + (ICON_WIDTH - $(png_width "$image")) / 2)) \
               label.drawing=on label="${LABELS[$1]}" label.font="$FONT" label.color=${LABEL_COLORS[$1]} \
               label.width=$((RIGHT_WIDTH + PADDING)) label.align=right label.padding_left=0 \
               label.padding_right=$PADDING \
               background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT "${HOVER[@]}" \
               script="$0 row ${ENTITIES[$1]}"
  sets+=(--subscribe "home.row.$1" mouse.entered mouse.exited mouse.clicked)
}

# slider_row <index>: under the device, from the start of its name, as audio.sh's volume. It sets
# the value when released
slider_row() {
  local name="home.slider.$1" width=$((WIDTH - PADDING - ICON_WIDTH - GAP - PADDING))
  names+=("$name")
  adds+=(--add slider "$name" popup.home $width)
  if [ -z "${SLIDERS[$1]}" ]; then
    sets+=(--set "$name" drawing=off)
    return
  fi
  sets+=(--set "$name" drawing=on padding_left=$((INSET + PADDING + ICON_WIDTH + GAP))
                       padding_right=$((INSET + PADDING)) icon.drawing=off label.drawing=off
                       slider.width=$width slider.percentage="${SLIDERS[$1]}" slider.highlight_color=$PRIMARY
                       slider.background.height=$SLIDER_HEIGHT slider.background.color=$SURFACE
                       slider.background.corner_radius=$((SLIDER_HEIGHT / 2))
                       slider.knob="$KNOB" slider.knob.font="SF Pro:Regular:16.0" slider.knob.color=$TEXT
                       background.drawing=on background.color=$TRANSPARENT background.height=22
                       script="$0 slider ${ENTITIES[$1]}"
         --subscribe "$name" mouse.clicked)
}

# mode_rows <index>: under a climate that is on, its mode, where a click lists the others below it
# or hides them; the climate listed is the one in MODES_FILE. In the list, from the start of the
# name, a row for each mode but off, the current one on a background as audio.sh's default
# device, where a click switches to it. A climate has the rows of all the modes, those not needed
# hidden
mode_rows() {
  local i=$1 entity=${ENTITIES[$1]} state=${STATES[$1]} k=0 mode image listed="" selected
  mode_look "$state"
  row "modes.$i" width=$WIDTH icon.drawing=on icon="$MODES_TITLE" icon.font="$FONT" icon.color=$SUBTEXT \
                 icon.padding_left=$((PADDING + ICON_WIDTH + GAP)) icon.padding_right=0 \
                 icon.width=$((WIDTH - RIGHT_WIDTH - PADDING)) icon.background.drawing=off \
                 label.drawing=on label="$MODE" label.font="$FONT" label.color=$PRIMARY \
                 label.width=$((RIGHT_WIDTH + PADDING)) label.align=right label.padding_left=0 \
                 label.padding_right=$PADDING \
                 background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT "${HOVER[@]}" \
                 script="$0 modes $entity"
  sets+=(--subscribe "home.modes.$i" mouse.entered mouse.exited mouse.clicked)
  [ "$(cat "$MODES_FILE" 2>/dev/null)" = "$entity" ] && listed=1
  for mode in ${HVAC_MODES[$1]}; do
    [ "$mode" != off ] && [ $k -lt $MAX_MODES ] || continue
    mode_look "$mode"
    image="$ICONS/${SYMBOL}_$COLOR.png"
    if [ "$mode" = "$state" ]; then
      selected=(background.color=$SURFACE script="$0 mode $entity current")
    else
      selected=(background.color=$TRANSPARENT script="$0 mode $entity $mode")
    fi
    row "mode.$i.$k" width=$WIDTH icon.drawing=on icon="$MODE" icon.font="$FONT" icon.color=$TEXT icon.align=left \
                     icon.padding_left=$((PADDING + 2 * (ICON_WIDTH + GAP))) icon.padding_right=0 icon.width=$WIDTH \
                     icon.background.drawing=on icon.background.image="$image" icon.background.image.scale=0.25 \
                     icon.background.image.padding_left=$((PADDING + ICON_WIDTH + GAP + (ICON_WIDTH - $(png_width "$image")) / 2)) \
                     label.drawing=off \
                     background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT "${selected[@]}"
    sets+=(--subscribe "home.mode.$i.$k" mouse.entered mouse.exited mouse.clicked)
    [ -n "$listed" ] || sets+=(--set "home.mode.$i.$k" drawing=off)
    k=$((k + 1))
  done
  for ((; k < MAX_MODES; k++)); do
    row "mode.$i.$k" drawing=off
  done
  if [ "$state" = off ] || [ "$state" = unavailable ] || [ -z "${HVAC_MODES[$1]}" ]; then
    sets+=(--set "home.modes.$i" drawing=off)
    for ((k = 0; k < MAX_MODES; k++)); do
      sets+=(--set "home.mode.$i.$k" drawing=off)
    done
  fi
}

# printer_rows <text>: under the plug while the printer prints, as the limits of claude.sh: a bar
# filled for the progress, the fill being the background of an empty icon as wide as the
# percentage over the background of the row, and the text, from the start of the name
printer_rows() {
  local status progress width=$((WIDTH - PADDING - ICON_WIDTH - GAP - PADDING)) color=$PRIMARY fill=()
  IFS=$'\x1f' read -r status progress _ <<< "$PRINTER"
  progress=${progress:-0}
  [ "$status" = pause ] && color=$YELLOW
  fill=(icon.background.drawing=off)
  [ "$progress" -gt 0 ] && fill=(icon.background.drawing=on icon.background.color=$color)
  row printer.bar width=$width padding_left=$((INSET + PADDING + ICON_WIDTH + GAP)) \
                  padding_right=$((INSET + PADDING)) \
                  icon.drawing=on icon="" icon.width=$((progress > 100 ? width : width * progress / 100)) \
                  icon.padding_left=0 icon.padding_right=0 "${fill[@]}" \
                  icon.background.height=$BAR_HEIGHT icon.background.corner_radius=$((BAR_HEIGHT / 2)) \
                  label.drawing=off \
                  background.drawing=on background.color=$SURFACE background.height=$BAR_HEIGHT \
                  background.corner_radius=$((BAR_HEIGHT / 2))
  row printer.text width=$WIDTH icon.drawing=on icon="$1" icon.font="$SMALL_FONT" icon.color=$SUBTEXT \
                   icon.padding_left=$((PADDING + ICON_WIDTH + GAP)) icon.padding_right=0 icon.width=dynamic \
                   label.drawing=off background.drawing=on background.color=$TRANSPARENT background.height=24
  if [ "$ONLINE" != true ] || ! printing "$status"; then
    sets+=(--set home.printer.bar drawing=off --set home.printer.text drawing=off)
  fi
}

render_popup() {
  local i j=0 g=0 name items widths details
  SYMBOLS=() COLORS=() NAME_COLORS=() LABELS=() LABEL_COLORS=() SLIDERS=() HVAC_MODES=()
  for ((i = 0; i < ${#ENTITIES[@]}; i++)); do
    device $i
    SYMBOLS+=("$SYMBOL") COLORS+=("$COLOR") NAME_COLORS+=("$NAME_COLOR") LABELS+=("$LABEL")
    LABEL_COLORS+=("$LABEL_COLOR") SLIDERS+=("$SLIDER") HVAC_MODES+=("$HVAC")
  done
  details="$(printer_text)"

  # The names, the states, also those of a click so that the popup doesn't change width, the
  # titles and the rows that span the popup, and the text under the printer
  local titles=() states=("${LABELS[@]}" "$ON" "$OFF" "100%" "$OPEN" "$CLOSED" "$OPENING" "$CLOSING"
                          "$CLEANING" "$RETURNING" "$DOCKED" "$PAUSED" "$IDLE" "$ERROR" "$RUN" "$RUNNING"
                          "$PRINTING" "$CONFIRM_OFF" "$TURNING_OFF" "$FAILED" "$UNAVAILABLE" "$HEAT" "$COOL"
                          "$DRY" "$FAN_ONLY" "$HEAT_COOL" "$AUTO")
  for ((i = 0; i < ${#ROWS[@]}; i += 2)); do
    [ "${ROWS[i]}" = group ] && titles+=("${ROWS[i + 1]}")
  done
  widths=($(text_widths HelveticaNeue-Bold 13 "${NAMES[@]}" "$MODES_TITLE" -- HelveticaNeue-Bold 13 "${states[@]}" \
                        -- HelveticaNeue-Bold 13 "${titles[@]}" "$UNREACHABLE" "$OPEN_DASHBOARD" \
                        -- HelveticaNeue-Medium 11 "$details"))
  RIGHT_WIDTH=${widths[1]:-0}
  WIDTH=$((PADDING + ICON_WIDTH + GAP + ${widths[0]:-0} + COLUMN_GAP + RIGHT_WIDTH + PADDING))
  [ $((PADDING + ${widths[2]:-0} + PADDING)) -gt $WIDTH ] && WIDTH=$((PADDING + ${widths[2]:-0} + PADDING))
  [ $((PADDING + ICON_WIDTH + GAP + ${widths[3]:-0} + PADDING)) -gt $WIDTH ] &&
    WIDTH=$((PADDING + ICON_WIDTH + GAP + ${widths[3]:-0} + PADDING))
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))

  items="$(sketchybar --query home | jq -r '.popup.items // [] | . - ["keep.home"] | join(" ")')"
  HOVER=()
  [ -z "$items" ] && HOVER=(background.color=$TRANSPARENT)

  # The groups, each title taller but the first, which parts them, and the devices with the mode
  # of the climate and their slider; or only the message while Home Assistant can't be reached
  for ((i = 0; i < ${#ROWS[@]}; i += 2)); do
    if [ "${ROWS[i]}" = group ]; then
      text_row title.$g $((g == 0 ? 30 : 38)) "${ROWS[i + 1]}" "$FONT" $TEXT
      g=$((g + 1))
      continue
    fi
    device_row $j
    [ "${ENTITIES[j]%%.*}" = climate ] && mode_rows $j
    case "${ENTITIES[j]%%.*}" in light | cover | climate) slider_row $j ;; esac
    [ "${ENTITIES[j]}" = "$PRINTER_PLUG" ] && printer_rows "$details"
    j=$((j + 1))
  done
  text_row unreachable 30 "$UNREACHABLE" "$FONT" $SUBTEXT
  if [ "$ONLINE" = true ]; then
    sets+=(--set home.unreachable drawing=off)
  else
    for name in "${names[@]}"; do
      case "$name" in home.unreachable) ;; *) sets+=(--set "$name" drawing=off) ;; esac
    done
  fi

  # Apart from the groups, as in system.sh
  text_row gap 10 "" "$SMALL_FONT" $SUBTEXT
  row dashboard width=$WIDTH icon.drawing=on icon="$OPEN_DASHBOARD" icon.font="$FONT" icon.color=$PRIMARY \
                icon.padding_left=$PADDING icon.padding_right=0 icon.width=dynamic label.drawing=off \
                background.drawing=on background.corner_radius=6 background.height=$ROW_HEIGHT "${HOVER[@]}" \
                script="$0 dashboard"
  sets+=(--subscribe home.dashboard mouse.entered mouse.exited mouse.clicked)
  space bottom 4

  if [ "$items" = "${names[*]}" ]; then
    sketchybar "${sets[@]}"
  else
    sketchybar --remove '/home\..*/' "${adds[@]}" "${sets[@]}"
  fi
}

# service <domain> <service> <JSON data>: on failure the row of NAME says so until the next update
service() {
  "$HELPER" call "$SERVER" "$1" "$2" "$3" || sketchybar --set "$NAME" label="$FAILED" label.color=$RED
}

# click <entity>: what a click on its row does. The plug of the printer turns off at the second
# click, unless the printer is working, which the script would refuse
click() {
  local entity=$1 i state data="{\"entity_id\":\"$1\"}"
  read_states
  for ((i = 0; i < ${#ENTITIES[@]}; i++)); do
    [ "${ENTITIES[i]}" = "$entity" ] && state=${STATES[i]}
  done
  [ "$ONLINE" = true ] && [ "$state" != unavailable ] || return
  if [ "$entity" = "$PRINTER_PLUG" ] && [ "$state" = on ]; then
    if printing "${PRINTER%%$'\x1f'*}"; then
      sketchybar --set "$NAME" label="$PRINTING" label.color=$RED
    elif [ "$(sketchybar --query "$NAME" | jq -r .label.value)" = "$CONFIRM_OFF" ]; then
      sketchybar --set "$NAME" label="$TURNING_OFF" label.color=$YELLOW
      service script turn_on "{\"entity_id\":\"$PRINTER_OFF\"}"
    else
      sketchybar --set "$NAME" label="$CONFIRM_OFF" label.color=$RED
    fi
    return
  fi
  case "${entity%%.*}:$state" in
    climate:off) service climate turn_on "$data" ;;
    climate:*) service climate turn_off "$data" ;;
    vacuum:cleaning) service vacuum return_to_base "$data" ;;
    vacuum:*) service vacuum start "$data" ;;
    script:*)
      sketchybar --set "$NAME" label="$RUNNING" label.color=$YELLOW
      service script turn_on "$data"
      ;;
    scene:*) service scene turn_on "$data" ;;
    *) service "${entity%%.*}" toggle "$data" ;;
  esac
}

# slider <entity>: the slider was released at PERCENTAGE. The temperature is the one of the range
# of the climate at that percentage, in its steps; until Home Assistant has it, which an air
# conditioner can take a while for, the row shows it as the target
slider() {
  local entity=$1 percent=${PERCENTAGE%.*} temperature label
  NAME=home.row.${NAME##*.}
  case "${entity%%.*}" in
    light)
      if [ "$percent" -gt 0 ]; then
        service light turn_on "{\"entity_id\":\"$entity\",\"brightness_pct\":$percent}"
      else
        service light turn_off "{\"entity_id\":\"$entity\"}"
      fi
      ;;
    cover) service cover set_cover_position "{\"entity_id\":\"$entity\",\"position\":$percent}" ;;
    climate)
      if ! temperature=$(jq -er --arg entity "$entity" --argjson percent "$percent" '
             .states[$entity].attributes | (.target_temp_step // 0.5) as $step
             | ((.min_temp + (.max_temp - .min_temp) * $percent / 100) / $step | round) * $step
             ' "$CACHE"); then
        sketchybar --set "$NAME" label="$FAILED" label.color=$RED
        return
      fi
      # 25,1° → 23°, or only the target when Home Assistant has no temperature
      label="$(sketchybar --query "$NAME" | jq -r .label.value)"
      case "$label" in
        *→*) label="${label%%→*}→ " ;;
        *) label="" ;;
      esac
      sketchybar --set "$NAME" label="$label$(printf '%s' "${temperature%.0}" | tr . ,)°"
      service climate set_temperature "{\"entity_id\":\"$entity\",\"temperature\":$temperature}"
      ;;
  esac
}

close_popup() {
  sketchybar --set home popup.drawing=off
  rm -f "$MODES_FILE"
}

# The popup rows: a device, a slider, which gives the percentage where it was released, and the
# last row. The plug of the printer forgets the first click when the mouse leaves it
case "$1" in
  # The rows and the sensors of the printer, if there is one
  watch)
    for entity in "$PRINTER_STATUS" "$PRINTER_PROGRESS" "$PRINTER_REMAINING"; do
      [ -n "$entity" ] && ENTITIES+=("$entity")
    done
    "$HELPER" watch "$SERVER" "$CACHE" "${ENTITIES[@]}" > /dev/null 2>&1 &
    exit 0
    ;;
  row)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited)
        sketchybar --set "$NAME" background.color=$TRANSPARENT
        if [ "$2" = "$PRINTER_PLUG" ]; then
          case "$(sketchybar --query "$NAME" | jq -r .label.value)" in
            "$CONFIRM_OFF" | "$PRINTING")
              read_states
              render_popup
              ;;
          esac
        fi
        ;;
      mouse.clicked) click "$2" ;;
    esac
    exit 0
    ;;
  slider)
    [ "$SENDER" = mouse.clicked ] && slider "$2"
    exit 0
    ;;
  # The mode of a climate lists the others, or hides them
  modes)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
      mouse.clicked)
        if [ "$(cat "$MODES_FILE" 2>/dev/null)" = "$2" ]; then
          rm -f "$MODES_FILE"
        else
          echo "$2" > "$MODES_FILE"
        fi
        read_states
        render_popup
        ;;
    esac
    exit 0
    ;;
  # A mode in the list hides it, and switches to the mode unless it is the current one; until Home
  # Assistant has it, the row of the mode shows it
  mode)
    case "$SENDER:$3" in
      mouse.entered:current | mouse.exited:current) ;;
      mouse.entered:*) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited:*) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
      mouse.clicked:*)
        rm -f "$MODES_FILE"
        read_states
        render_popup
        [ "$3" = current ] && exit 0
        i=${NAME#home.mode.}
        NAME=home.modes.${i%.*}
        mode_look "$3"
        sketchybar --set "$NAME" label="$MODE"
        service climate set_hvac_mode "{\"entity_id\":\"$2\",\"hvac_mode\":\"$3\"}"
        ;;
    esac
    exit 0
    ;;
  dashboard)
    case "$SENDER" in
      mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
      mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
      mouse.clicked)
        close_popup
        open "$DASHBOARD"
        ;;
    esac
    exit 0
    ;;
esac

# home_printer only opens the popup. The popup is set again when it opens and while it is open:
# measuring the texts takes a moment, too long for every change while nobody sees it
case "$SENDER" in
  mouse.clicked)
    if [ "$(sketchybar --query home | jq -r .popup.drawing)" = on ]; then
      close_popup
    else
      sketchybar --set home popup.drawing=on
      read_states
      render_popup
    fi
    ;;
  mouse.exited.global) close_popup ;;
  # The connection is gone after sleep, though the helper would know only at its next ping
  system_woke) pkill -USR1 -x home_assistant ;;
  *)
    [ "$NAME" = home ] || exit 0
    read_states
    update_bar
    if [ "$SENDER" != home_assistant_change ] || [ "$(sketchybar --query home | jq -r .popup.drawing)" = on ]; then
      render_popup
    fi
    ;;
esac
