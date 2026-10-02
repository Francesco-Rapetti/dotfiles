#!/usr/bin/env bash

# Docker: the docker item shows the whale of Docker Desktop with how many containers are running, in
# red when one of them is unhealthy or restarting, and hides while Docker doesn't answer. Its popup
# has the engine (Docker Desktop, its version, its CPUs, memory and images), then the running
# containers, each with an icon for its state, the CPU and the memory it uses, the image, the
# published ports and how long it has been up, then the row that opens Docker Desktop. While the
# popup is open docker stats refreshes the CPU and the memory every few seconds.
# sketchybarrc runs this with watch, which follows docker events and triggers docker_change when a
# container starts, stops, pauses or changes health, and when Docker starts or stops; the item runs
# it with no arguments, the last row of the popup with open.
# The icons are images of helpers/docker_icons.js: the whale is Docker Desktop's, the others SF
# Symbols in the colors below

source "$CONFIG_DIR/colors.sh"

ICONS="$CONFIG_DIR/helpers/docker_icons"
STATS="${TMPDIR:-/tmp}/sketchybar_docker_stats"
LOCK="${TMPDIR:-/tmp}/sketchybar_docker.lock"
DOCKER_DESKTOP=/Applications/Docker.app

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
INSET=4              # between the rows and the edge of the popup, as in apple.sh
PADDING=8            # inside the rows
STATE_ICON=14        # the column of the state icons
GAP=8                # after the state icons, and between the names and the usage
NAME_WIDTH=160       # the column of the names, cut to fit it
USAGE_WIDTH=110      # the widest usage, 100,0% · 1023 MB
ROW_HEIGHT=24        # of a row of text, unless it sets its own
CONTAINER_HEIGHT=26  # of the name of a container, with room above
DETAILS_HEIGHT=16    # of the line under it, close to the name
TITLE_HEIGHT=38      # of the title of the containers, with room above
MAX=10               # the containers listed, the others are counted in the row after them
POLL=5               # seconds between the checks of watch while Docker doesn't answer
# Fixed, so the refresh every few seconds needs no measuring: the names and the details are cut
WIDTH=$((PADDING + STATE_ICON + GAP + NAME_WIDTH + GAP + USAGE_WIDTH + PADDING))
DETAILS_WIDTH=$((WIDTH - PADDING - STATE_ICON - GAP - PADDING))

OPEN_DESKTOP="Apri Docker Desktop"

# SketchyBar started at login has only the system PATH: also look where Docker Desktop, Homebrew
# (e.g. for colima) and OrbStack put docker
find_docker() {
  local candidate
  for candidate in "$(type -P docker)" /usr/local/bin/docker "$HOME/.docker/bin/docker" \
                   /opt/homebrew/bin/docker "$HOME/.orbstack/bin/docker" \
                   "$DOCKER_DESKTOP/Contents/Resources/bin/docker"; do
    [ -x "$candidate" ] && echo "$candidate" && return
  done
  return 1
}

# docker <arguments>: perl's alarm stops it if Docker hangs, e.g. while it starts
docker() {
  [ -n "$DOCKER" ] && perl -e 'alarm shift; exec @ARGV' 10 "$DOCKER" "$@" 2>/dev/null
}

# png_width <png>: in points, from the width in px in the PNG header, 4 px per point
png_width() {
  local a b c d
  read -r a b c d < <(od -An -tu1 -j16 -N4 "$1")
  echo $((((a << 24 | b << 16 | c << 8 | d) + 3) / 4))
}

# bar_icon: sets ICON to the icon settings of the item, the whale or, without Docker Desktop, a box,
# as for the claude item: an image ignores the padding of the icon and starts at its left edge, so
# image.padding_left leaves the room before the symbols of the other items (icon.padding_left plus
# their origin), in an icon as wide as that and the image
bar_icon() {
  local image="$ICONS/whale.png"
  [ -f "$image" ] || image="$ICONS/shippingbox.fill_text.png"
  ICON=(icon="" icon.width=$((12 + $(png_width "$image"))) icon.background.drawing=on
        icon.background.image="$image" icon.background.image.scale=0.25 icon.background.image.padding_left=12)
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

# plural <count> <singular> <plural>: e.g. 1 attivo, 3 attivi
plural() {
  if [ "$1" -eq 1 ]; then echo "$1 $2"; else echo "$1 $3"; fi
}

# up_for <start, Unix time>: e.g. da 2 h
up_for() {
  local up=$(($(date +%s) - $1))
  if [ $up -ge 86400 ]; then echo "da $((up / 86400)) g"
  elif [ $up -ge 3600 ]; then echo "da $((up / 3600)) h"
  elif [ $up -ge 60 ]; then echo "da $((up / 60)) min"
  else echo "appena avviato"
  fi
}

# fit (<font> <size> <width> <count> <text>...)...: each text on a line, cut with … to fit the width
# in points in its font. SketchyBar can't cut a text by its width, and the names and the images of
# the containers can be long
fit() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run(argv) {
  const lines = []
  for (let i = 0; i < argv.length; i += 4 + Number(argv[i + 3])) {
    const [name, size, width, count] = argv.slice(i, i + 4)
    const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize(name, Number(size)), $.NSFontAttributeName)
    const fits = text => $(text).sizeWithAttributes(font).width <= Number(width)
    for (let text of argv.slice(i + 4, i + 4 + Number(count))) {
      if (!fits(text)) {
        while (text.length > 1 && !fits(text + '…')) text = text.slice(0, -1)
        text = text.trimEnd() + '…'
      }
      lines.push(text)
    }
  }
  return lines.join('\n')
}
EOF
}

# The CPU and the memory of each running container, as <name>\t<tenths of a percent>\t<MB>.
# docker stats measures them for a couple of seconds
measure() {
  docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' |
    awk -F'\t' '{
      split($3, memory, " ")
      value = memory[1] + 0
      unit = memory[1]
      sub(/^[0-9.]+/, "", unit)
      if (unit == "B") value /= 1048576
      else if (unit == "KiB" || unit == "kB") value /= 1024
      else if (unit == "GiB" || unit == "GB") value *= 1024
      else if (unit == "TiB" || unit == "TB") value *= 1048576
      printf "%s\t%d\t%d\n", $1, $2 * 10 + 0.5, value + 0.5
    }'
}

# query <item>: sketchybar --query, which answers nothing while SketchyBar is busy, e.g. adding the
# rows of a popup
query() {
  local answer i
  for ((i = 0; i < 25; i++)); do
    answer="$(sketchybar --query "$1" 2>/dev/null)"
    [ -n "$answer" ] && echo "$answer" && return
    sleep 0.2
  done
  return 1
}

# Each render lists all the popup rows, as in system.sh: row <name> <properties>... puts one at the
# bottom. names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are always the same, the ones not needed hidden: removing the row under the mouse would
# close the popup (mouse.exited.global). The rows are INSET from the edges, so the highlight doesn't
# touch them
row() {
  local name="docker.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.docker)
  sets+=(--set "$name" drawing=on padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# A row with a text on the left and, if given, one on the right, as in system.sh. A row is as tall
# as its background, and SketchyBar draws it in a window of that height which clips what is out of
# it: the texts stay centered and the rows that need more room above or less set their height
# text_row <name> <height> <left> <left font> <left color> [<right> <right font> <right color>]
text_row() {
  local properties=(width=$WIDTH icon.drawing=on icon="$3" icon.font="$4" icon.color=$5
                    icon.padding_left=$PADDING icon.padding_right=0 label.padding_left=0
                    icon.background.drawing=off
                    background.drawing=on background.color=$TRANSPARENT background.height=$2)
  if [ -n "$6" ]; then
    # A fixed width includes the padding
    properties+=(icon.width=$((WIDTH - USAGE_WIDTH - PADDING))
                 label.drawing=on label="$6" label.font="$7" label.color=$8 label.width=$((USAGE_WIDTH + PADDING))
                 label.align=right label.padding_right=$PADDING)
  else
    properties+=(icon.width=dynamic label.drawing=off)
  fi
  row "$1" "${properties[@]}"
}

# details_row <name> <height> <text>: a line in line with the names of the containers
details_row() {
  row "$1" width=$WIDTH icon.drawing=on icon="$3" icon.font="$SMALL_FONT" icon.color=$SUBTEXT \
           icon.padding_left=$((PADDING + STATE_ICON + GAP)) icon.padding_right=0 icon.width=dynamic \
           icon.background.drawing=off label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.height=$2
}

# render [<property of the docker item>...]: the popup rows with the engine and the running
# containers, with the CPU and the memory that measure last saved
render() {
  # follow renders more than once
  names=() adds=() sets=()
  local os version cpus memory images stopped
  IFS=$'\x1f' read -r os version cpus memory images stopped < <(
    docker info --format '{{json .}}' |
      jq -r '[.OperatingSystem, .ServerVersion, .NCPU, (.MemTotal / 1048576 | floor), .Images,
              .ContainersStopped] | map(tostring) | join("\u001f")')
  # Docker stopped meanwhile: the next update hides the item
  [ -n "$version" ] || return

  # name, image without the registry and the digest, state, health, start as Unix time, published
  # ports, CPU and memory, sorted by name: those of a Compose project are together
  local ids containers=""
  ids=($(docker ps -q))
  if [ ${#ids[@]} -gt 0 ]; then
    containers="$(docker inspect "${ids[@]}" |
      jq -r --arg stats "$(cat "$STATS" 2>/dev/null)" '
        ($stats | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1:]})
         | from_entries) as $usage
        | sort_by(.Name)[]
        | (.Name | ltrimstr("/")) as $name
        | [$name,
           (.Config.Image | sub("@sha256:.*"; "") | sub("^.*/"; "")),
           .State.Status,
           (.State.Health.Status // ""),
           (.State.StartedAt | sub("\\.[0-9]+"; "") | fromdateiso8601 | tostring),
           ([.NetworkSettings.Ports // {} | .[] // [] | .[].HostPort | tonumber] | unique
            | map(":\(.)") | join(", ")),
           ($usage[$name] // ["", ""])[]]
        | join("\u001f")')"
  fi

  local count=0 shown_names=() details=() icons=() usages=()
  local name image state health started ports cpu used detail icon
  while IFS=$'\x1f' read -r name image state health started ports cpu used; do
    [ -n "$name" ] || continue
    count=$((count + 1))
    [ $count -le $MAX ] || continue
    # The color of the bar: red here is red there
    case "$state:$health" in
      paused:*) icon=pause.circle.fill_yellow detail="in pausa" ;;
      restarting:*) icon=arrow.clockwise.circle.fill_red detail="in riavvio" ;;
      *:unhealthy) icon=exclamationmark.circle.fill_red detail="health check fallito" ;;
      *:starting) icon=circle.fill_yellow detail="in avvio" ;;
      *) icon=circle.fill_green detail="$(up_for "$started")" ;;
    esac
    shown_names+=("$name") icons+=("$icon")
    details+=("$image${ports:+ · $ports} · $detail")
    if [ -n "$cpu" ]; then usages+=("$(percent "$cpu") · $(size "$used")"); else usages+=(""); fi
  done <<< "$containers"

  local fitted=() line
  if [ ${#shown_names[@]} -gt 0 ]; then
    while IFS= read -r line; do fitted+=("$line"); done < <(
      fit HelveticaNeue-Bold 13 $NAME_WIDTH ${#shown_names[@]} "${shown_names[@]}" \
          HelveticaNeue-Medium 11 $DETAILS_WIDTH ${#details[@]} "${details[@]}")
  fi

  local title=Docker
  case "$os" in "Docker Desktop" | OrbStack) title="$os" ;; esac
  space top 4
  text_row engine $ROW_HEIGHT "$title" "$FONT" $TEXT "Engine $version" "$SMALL_FONT" $SUBTEXT
  text_row resources $DETAILS_HEIGHT "$cpus CPU · $(size "$memory") di memoria · $(plural "$images" immagine immagini)" \
           "$SMALL_FONT" $SUBTEXT
  local summary
  summary="$(plural $count attivo attivi)"
  [ "${stopped:-0}" -gt 0 ] && summary="$summary · $(plural "$stopped" fermo fermi)"
  text_row title $TITLE_HEIGHT "Container" "$FONT" $TEXT "$summary" "$SMALL_FONT" $SUBTEXT

  # SketchyBar draws only an icon and a label in a row, as in system.sh: the name is the text of the
  # icon, after the image of the state in its background, and the usage the label
  local i shown=${#shown_names[@]}
  for ((i = 0; i < MAX; i++)); do
    if [ $i -ge $shown ]; then
      row "c.$i"
      sets+=(drawing=off)
      row "c.$i.details"
      sets+=(drawing=off)
      continue
    fi
    row "c.$i" width=$WIDTH icon.drawing=on icon="${fitted[i]}" icon.font="$FONT" icon.color=$TEXT \
               icon.padding_left=$((PADDING + STATE_ICON + GAP)) icon.padding_right=0 \
               icon.width=$((WIDTH - USAGE_WIDTH - PADDING)) \
               icon.background.drawing=on icon.background.image="$ICONS/${icons[i]}.png" \
               icon.background.image.scale=0.25 icon.background.image.padding_left=$PADDING \
               label.drawing=on label="${usages[i]}" label.font="$FONT" label.color=$SUBTEXT \
               label.width=$((USAGE_WIDTH + PADDING)) label.align=right label.padding_left=0 \
               label.padding_right=$PADDING \
               background.drawing=on background.color=$TRANSPARENT background.height=$CONTAINER_HEIGHT
    details_row "c.$i.details" $DETAILS_HEIGHT "${fitted[shown + i]}"
  done

  # Under the list: how many more, or that there are none
  if [ $count -gt $MAX ]; then
    details_row more $ROW_HEIGHT "e altri $((count - MAX))"
  elif [ $count -eq 0 ]; then
    text_row more $ROW_HEIGHT "Nessun container in esecuzione" "$SMALL_FONT" $SUBTEXT
  else
    row more
    sets+=(drawing=off)
  fi

  # Apart from the list, as in system.sh
  text_row open.gap 10 "" "$SMALL_FONT" $SUBTEXT
  row open width=$WIDTH icon.drawing=on icon="$OPEN_DESKTOP" icon.font="$FONT" icon.color=$PRIMARY \
           icon.padding_left=$PADDING icon.padding_right=0 icon.width=dynamic \
           icon.background.drawing=off label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
           background.height=$ROW_HEIGHT script="$0 open"
  sets+=(--subscribe docker.row.open mouse.entered mouse.exited mouse.clicked)
  if [ "$title" != "Docker Desktop" ] || [ ! -d "$DOCKER_DESKTOP" ]; then
    sets+=(--set docker.row.open.gap drawing=off --set docker.row.open drawing=off)
  fi
  space bottom 4

  if [ "$(query docker | jq -r '.popup.items // [] | . - ["keep.docker"] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" "$@"
  else
    sketchybar --remove '/docker\.row\..*/' "${adds[@]}" "${sets[@]}" "$@"
  fi
}

# popup: on or off
popup() {
  query docker | jq -r '.popup.drawing // "off"'
}

# update: hides the item while Docker doesn't answer, otherwise how many containers are running, in
# red when one is unhealthy or restarting and dimmed when none is, and the popup rows, so it opens
# on them
update() {
  local states
  if ! states="$(docker ps --format '{{.State}}\t{{.Status}}')"; then
    sketchybar --set docker drawing=off popup.drawing=off
    return
  fi
  local count=0 color=$TEXT state status
  while IFS=$'\t' read -r state status; do
    [ -n "$state" ] || continue
    count=$((count + 1))
    case "$state:$status" in
      restarting:* | *"(unhealthy)"*) color=$RED ;;
    esac
  done <<< "$states"
  [ $count -eq 0 ] && color=$SUBTEXT
  bar_icon
  render --set docker drawing=on label=$count label.color=$color "${ICON[@]}"
}

# The lock holds the pid of the background job, which bash 3.2 has no $BASHPID for
lock() {
  shlock -f "$LOCK" -p "$(exec sh -c 'echo $PPID')"
}

# follow: while the popup is open, measures the CPU and the memory again and shows them; one at a
# time, though every click that opens the popup starts one. First the rows as they are now, e.g.
# how long the containers have been up
follow() {
  lock || return
  render
  while [ "$(popup)" = on ]; do
    measure > "$STATS.tmp" && mv "$STATS.tmp" "$STATS"
    [ "$(popup)" = on ] && render
    sleep 1
  done
  rm -f "$LOCK"
}

# watch: triggers docker_change when Docker starts or stops and, while it runs, a second after the
# last of a burst of container events, e.g. docker compose up. Until Docker answers it asks again
# every POLL seconds. --since replays what happened between the check and docker events.
# A reload of SketchyBar starts a new one: the old one stops, with docker events
watch() {
  trap 'pkill -P $$; exit 0' TERM INT HUP
  local since
  while :; do
    DOCKER="$(find_docker)"
    since=$(date +%s)
    if docker version --format '{{.Server.Version}}' > /dev/null; then
      sketchybar --trigger docker_change
      while read -r _; do
        while read -t 1 -r _; do :; done
        sketchybar --trigger docker_change
      done < <(exec "$DOCKER" events --since $since --filter type=container \
                 --filter event=start --filter event=die --filter event=pause --filter event=unpause \
                 --filter event=health_status --filter event=rename --format '{{.Action}}' 2>/dev/null)
      sketchybar --trigger docker_change
    fi
    sleep $POLL &
    wait $!
  done
}

DOCKER="$(find_docker)"

if [ "$1" = watch ]; then
  watch
  exit 0
fi

# The last row of the popup
if [ "$1" = open ]; then
  case "$SENDER" in
    mouse.entered) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked)
      sketchybar --set docker popup.drawing=off
      open -a "$DOCKER_DESKTOP"
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  # The popup shows the CPU and the memory of the last time it was open until docker stats measures
  # them again, a couple of seconds later
  mouse.clicked)
    if [ "$(popup)" = on ]; then
      sketchybar --set docker popup.drawing=off
    else
      sketchybar --set docker popup.drawing=on
      follow &
    fi
    ;;
  mouse.exited.global) sketchybar --set docker popup.drawing=off ;;
  *) update ;;
esac
