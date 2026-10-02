#!/usr/bin/env bash

# CPU, GPU and memory usage, which helpers/system_stats sends with system_stats_change every 2
# seconds when they change. CPU and GPU turn yellow from 75% and red from 90%; the memory has the
# color of its pressure, as in Activity Monitor: macOS keeps the memory nearly full with caches and
# compressed pages, so the percentage alone says little. The GPU hides when macOS doesn't report it.
# A click on any of them opens the popup of the system bracket: for each a bar, the details and the
# apps that use it most, with their icon, then the row that opens Activity Monitor. While the popup
# is open the helper adds the details to each update (SIGUSR1 turns them on, SIGUSR2 off), so the
# popup changes with the bar
# The ram item, the only one on every display, runs this for the updates and the popup, cpu and gpu
# for their clicks, the last row of the popup with activity
# The icons are SF Symbols, so they need the SF Pro font (brew install --cask font-sf-pro)

source "$CONFIG_DIR/colors.sh"

WARNING=75   # from this percentage CPU and GPU turn yellow
CRITICAL=90  # and from this one red

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
INSET=4            # between the rows and the edge of the popup, as in apple.sh
PADDING=8          # inside the rows
APP_ICON=16        # the column of the app icons
GAP=8              # after the app icons, and between the names and the values
NAME_WIDTH=190     # the column of the names, which helpers/system_stats cuts to fit it
VALUE_WIDTH=48     # the widest value, 88,8 GB
TOP=5              # the apps of each list, as many as helpers/system_stats sends
ROW_HEIGHT=24      # of a row of text, unless it sets its own
APP_HEIGHT=22      # of the rows of the lists
FIRST_TITLE_HEIGHT=30
TITLE_HEIGHT=38    # of the title of the other sections, with room above
BAR_HEIGHT=6
# Fixed, so the update every 2 seconds needs no measuring: it fits the widest details too
WIDTH=$((PADDING + APP_ICON + GAP + NAME_WIDTH + GAP + VALUE_WIDTH + PADDING))

ACTIVITY_MONITOR="Apri Monitoraggio Attività"

# color_for <percent> <color below the warning>
color_for() {
  if [ "$1" -ge $CRITICAL ]; then
    echo $RED
  elif [ "$1" -ge $WARNING ]; then
    echo $YELLOW
  else
    echo "$2"
  fi
}

# pressure_color <color of the normal pressure>
pressure_color() {
  case "$PRESSURE" in
    warning) echo $YELLOW ;;
    critical) echo $RED ;;
    *) echo "$1" ;;
  esac
}

# percent <tenths of a percent>: e.g. 4,3%
percent() {
  echo "$(($1 / 10)),$(($1 % 10))%"
}

# size <MB>: e.g. 850 MB or 3,2 GB
size() {
  if [ "$1" -ge 1024 ]; then
    local tenths=$((($1 * 10 + 512) / 1024))
    echo "$((tenths / 10)),$((tenths % 10)) GB"
  else
    echo "$1 MB"
  fi
}

# Each render lists all the popup rows, as in claude.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are always the same, the ones not needed hidden, as in battery.sh: removing the row under
# the mouse would close the popup (mouse.exited.global). The rows are INSET from the edges, so the
# highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="system.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.system)
  sets+=(--set "$name" drawing=on padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room below the last row, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# text_row <name> <height> <left> <left font> <left color> [<right> <right font> <right color>]
text_row() {
  local properties=(width=$WIDTH icon.drawing=on icon="$3" icon.font="$4" icon.color=$5
                    icon.padding_left=$PADDING icon.padding_right=0 label.padding_left=0
                    background.drawing=on background.color=$TRANSPARENT background.height=$2)
  if [ -n "$6" ]; then
    # A fixed width includes the padding
    properties+=(icon.width=$((WIDTH - VALUE_WIDTH - PADDING))
                 label.drawing=on label="$6" label.font="$7" label.color=$8 label.width=$((VALUE_WIDTH + PADDING))
                 label.align=right label.padding_right=$PADDING)
  else
    properties+=(icon.width=dynamic label.drawing=off)
  fi
  row "$1" "${properties[@]}"
}

# bar_row <name> <percent> <color>: as in claude.sh, the fill is the background of an empty icon as
# wide as the percentage, over the background of the row
bar_row() {
  local width=$((WIDTH - 2 * PADDING)) fill=(icon.background.drawing=off)
  [ "$2" -gt 0 ] && fill=(icon.background.drawing=on icon.background.color=$3)
  row "$1" width=$width padding_left=$((INSET + PADDING)) padding_right=$((INSET + PADDING)) \
           icon.drawing=on icon="" icon.width=$(($2 > 100 ? width : width * $2 / 100)) \
           icon.padding_left=0 icon.padding_right=0 "${fill[@]}" \
           icon.background.height=$BAR_HEIGHT icon.background.corner_radius=$((BAR_HEIGHT / 2)) \
           label.drawing=off \
           background.drawing=on background.color=$SURFACE background.height=$BAR_HEIGHT \
           background.corner_radius=$((BAR_HEIGHT / 2))
}

# section <name> <title> <percent> <color> <bar color> <details>...: the title with the percentage,
# the bar and a row for each details, the first with more room above it
section() {
  local name=$1 height=$TITLE_HEIGHT line=0 details
  [ "$name" = cpu ] && height=$FIRST_TITLE_HEIGHT
  text_row "$name.title" $height "$2" "$FONT" $TEXT "$3%" "$FONT" "$4"
  bar_row "$name.bar" "$3" "$5"
  shift 5
  for details in "$@"; do
    text_row "$name.details.$line" $((line == 0 ? 26 : 20)) "$details" "$SMALL_FONT" $SUBTEXT
    line=$((line + 1))
  done
}

# app_rows <name> <format> <lines>: the TOP rows of a list, as in audio.sh: SketchyBar draws only an
# icon and a label in a row, so the name is the text of the icon, after the app icon in its
# background, and the value the label. The processes outside of an app have no icon
app_rows() {
  local name=$1 format=$2 i=0 bundle app value image
  while IFS=$'\x1f' read -r bundle app value; do
    [ -n "$app" ] || continue
    image=(icon.background.drawing=off)
    [ -n "$bundle" ] && image=(icon.background.drawing=on icon.background.image="app.$bundle"
                               icon.background.image.scale=0.5 icon.background.image.padding_left=$PADDING)
    row "$name.$i" width=$WIDTH icon.drawing=on icon="$app" icon.font="$FONT" icon.color=$TEXT \
                   icon.padding_left=$((PADDING + APP_ICON + GAP)) icon.padding_right=0 \
                   icon.width=$((WIDTH - VALUE_WIDTH - PADDING)) "${image[@]}" \
                   label.drawing=on label="$($format "$value")" label.font="$FONT" label.color=$SUBTEXT \
                   label.width=$((VALUE_WIDTH + PADDING)) label.align=right label.padding_left=0 \
                   label.padding_right=$PADDING \
                   background.drawing=on background.color=$TRANSPARENT background.height=$APP_HEIGHT
    i=$((i + 1))
  done <<< "$3"
  for ((; i < TOP; i++)); do
    row "$name.$i"
    sets+=(drawing=off)
  done
}

render_popup() {
  section cpu "CPU" "$CPU" "$(color_for "$CPU" $TEXT)" "$(color_for "$CPU" $PRIMARY)" \
          "Sistema $(percent "$CPU_SYSTEM") · Utente $(percent "$CPU_USER") · Inattivo $(percent "$CPU_IDLE")"
  app_rows cpu percent "$CPU_TOP"

  local model="$GPU_MODEL"
  [ -n "$GPU_CORES" ] && model="${model:+$model · }$GPU_CORES core"
  section gpu "GPU" "${GPU:-0}" "$(color_for "${GPU:-0}" $TEXT)" "$(color_for "${GPU:-0}" $PRIMARY)" "$model"
  app_rows gpu percent "$GPU_TOP"
  local name
  if [ -z "$GPU" ]; then
    for name in "${names[@]}"; do [[ $name == system.row.gpu.* ]] && sets+=(--set "$name" drawing=off); done
  fi

  local pressure=normale used
  case "$PRESSURE" in
    warning) pressure=alta ;;
    critical) pressure=critica ;;
  esac
  used="$(size "$MEMORY_USED") di $((MEMORY_TOTAL / 1024)) GB"
  [ "${SWAP_USED:-0}" -gt 0 ] && used="$used · swap $(size "$SWAP_USED")"
  section memory "Memoria" "$RAM" "$(pressure_color $TEXT)" "$(pressure_color $PRIMARY)" \
          "$used · pressione $pressure" \
          "App $(size "$MEMORY_APP") · wired $(size "$MEMORY_WIRED") · compressa $(size "$MEMORY_COMPRESSED")"
  app_rows memory size "$MEMORY_TOP"

  # Apart from the sections, as in battery.sh
  text_row activity.gap 10 "" "$SMALL_FONT" $SUBTEXT
  row activity width=$WIDTH icon.drawing=on icon="$ACTIVITY_MONITOR" icon.font="$FONT" icon.color=$PRIMARY \
               icon.padding_left=$PADDING icon.padding_right=0 icon.width=dynamic label.drawing=off \
               background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
               background.height=$ROW_HEIGHT script="$0 activity"
  sets+=(--subscribe system.row.activity mouse.entered mouse.exited mouse.clicked)
  space bottom 4

  if [ "$(sketchybar --query system | jq -r '.popup.items // [] | . - ["keep.system"] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "$@" "${sets[@]}"
  else
    sketchybar --remove '/system\.row\..*/' "${adds[@]}" "${sets[@]}" "$@"
  fi
}

close_popup() {
  sketchybar --set system popup.drawing=off
  pkill -USR2 -x system_stats
}

# The last row of the popup
if [ "$1" = activity ]; then
  case "$SENDER" in
    mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked)
      close_popup
      open -a "Activity Monitor"
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  system_stats_change)
    bar=()
    if [ -n "$CPU" ]; then
      color=$(color_for "$CPU" $TEXT)
      bar+=(--set cpu label="$CPU%" icon.color=$color label.color=$color)
    fi
    if [ -n "$GPU" ]; then
      color=$(color_for "$GPU" $TEXT)
      bar+=(--set gpu drawing=on label="$GPU%" icon.color=$color label.color=$color)
    else
      bar+=(--set gpu drawing=off)
    fi
    [ -n "$RAM" ] && bar+=(--set ram label="$RAM%" icon.color=$(pressure_color $TEXT) label.color=$(pressure_color $TEXT))
    # Only with the popup open: the update that follows SIGUSR1 has the details, the others don't
    if [ -n "${CPU_TOP+set}" ]; then
      render_popup "${bar[@]}"
    else
      sketchybar "${bar[@]}"
    fi
    ;;
  # The popup shows the rows of the last time it was open until the details come, a quarter of a
  # second later
  mouse.clicked)
    if [ "$(sketchybar --query system | jq -r .popup.drawing)" = on ]; then
      close_popup
    else
      sketchybar --set system popup.drawing=on
      pkill -USR1 -x system_stats
    fi
    ;;
  mouse.exited.global) close_popup ;;
esac
