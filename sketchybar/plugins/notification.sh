#!/usr/bin/env bash

# Notifications, as two badges at the right end of the bar that share a popup. The green one,
# notification_apps, counts what the apps of notification_apps.conf have to read: the badges on
# their icons in the Dock, e.g. the unread messages of Slack; and the crashes of SketchyBar that
# ../start.sh logged. The red one, notification_brew, counts the updates for the Homebrew packages
# in the Brewfile at the root of the dotfiles. Each hides when it has nothing to count.
# The popup lists the crashes, in a row that opens their log, then the apps with their badge, where
# a click opens one, then the packages with the installed and the new version: a click on one
# upgrades it, "Aggiorna tutto" upgrades them all.
# AeroSpace keeps running the old version after an upgrade: until it restarts the popup also has
# "Riavvia AeroSpace", counted in the red badge, and the notification of the upgrade opens the popup.
# macOS doesn't tell when a badge changes: sketchybarrc runs this with watch, which reads them, and
# the crashes, every POLL seconds and triggers notification_change when they change. The
# notification item runs this with no arguments, each popup row with crash, open <bundle id>,
# restart or the <formula|cask> <name> pairs it upgrades. SketchyBar kills its scripts after 60 seconds, so brew runs in the background

APPS="$CONFIG_DIR/notification_apps.conf"
BREWFILE="$CONFIG_DIR/../Brewfile"
OUTDATED="${TMPDIR:-/tmp}/sketchybar_notification_brew"  # what check found, for render
RENDER_LOCK="${TMPDIR:-/tmp}/sketchybar_notification.lock"
LOCK="${TMPDIR:-/tmp}/sketchybar_brew.lock"
BUSY="${TMPDIR:-/tmp}/sketchybar_brew_busy"
LOG="$HOME/Library/Logs/sketchybar-brew.log"
CRASHES="${TMPDIR:-/tmp}/sketchybar_crashes"  # from ../start.sh: the time of each crash not seen yet
CRASH_LOG="$HOME/Library/Logs/sketchybar-crash.log"

source "$CONFIG_DIR/colors.sh"

CRASHED="Crash di SketchyBar"
CRASHED_MANY="crash di SketchyBar"  # after their number
UPGRADING="aggiornamento…"
UPGRADE_ALL="Aggiorna tutto"
RESTART="Riavvia AeroSpace"
RESTARTING="Riavvio di AeroSpace…"
POLL=2          # seconds between the readings of the badges in watch
INSET=4         # between the rows and the edge of the popup, as in apple.sh
PADDING=8       # inside the rows
APP_ICON=16     # the column of the app icons, as in system.sh
ICON_GAP=8      # after the app icons
GAP=16          # between the names and the badges or the versions
SECTION_GAP=8   # between the apps and the packages
BADGE_WIDTH=18  # of the badges in the bar: round up to two digits, then a pill
BADGE_INSET=3   # on both sides of the number of a pill
DIGIT_WIDTH=6   # every digit of the badge font, Helvetica Neue Bold 11
BADGE_GAP=4     # between the two badges

# brew update runs only in check, so brew upgrade installs the versions the popup shows.
# By default brew upgrade also upgrades the installed packages that depend on the upgraded ones:
# the popup upgrades only its packages (and the dependencies they need)
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1

# SketchyBar ignores SIGCHLD and its scripts inherit that: brew, in Ruby, then gets no exit status
# from the commands it runs and fails, e.g. brew upgrade in Hardware::CPU.cores.
# A shell can't restore a signal that was ignored when it started, perl can
brew() {
  /usr/bin/perl -e '$SIG{CHLD} = "DEFAULT"; exec @ARGV' brew "$@"
}

# <formula|cask> <name> for each package of the Brewfile
brewfile_packages() {
  sed -nE 's/^brew "([^"]+)".*/formula \1/p; s/^cask "([^"]+)".*/cask \1/p' "$BREWFILE"
}

# <formula|cask> <name> <installed version> <new version> for each outdated package of the Brewfile
outdated_packages() {
  local packages kind names
  packages="$(brewfile_packages)"
  for kind in formula cask; do
    names=($(awk -v kind=$kind '$1 == kind {print $2}' <<< "$packages"))
    # With no names brew outdated lists every outdated package
    [ ${#names[@]} -gt 0 ] || continue
    # e.g. "felixkratz/formulae/borders (1.8.4) < 1.9.0": with more versions installed, the last one
    brew outdated --verbose --$kind "${names[@]}" 2>/dev/null |
      sed -nE "s/^([^ ]+) \((.*, )?([^ ]+)\) (<|!=) (.+)$/$kind \1 \3 \5/p"
  done
}

# The versions of the aerospace command and of the running AeroSpace, on one line. The second one
# is missing while AeroSpace isn't running
aerospace_versions() {
  aerospace --version 2>/dev/null | sed -nE 's/^.* version: ([0-9][^ ]*).*/\1/p' | paste -sd' ' -
}

# The version AeroSpace restarts on, if it is running an older one
aerospace_restart_version() {
  local command running
  read -r command running <<< "$(aerospace_versions)"
  [ -n "$running" ] && [ "$running" != "$command" ] && echo "$command"
}

# <bundle id>\t<name>\t<badge> for each app of notification_apps.conf with a badge on its icon in
# the Dock, in the order of the file. lsappinfo takes the bundle id or the name, and knows only the
# running apps, e.g.
# "CFBundleIdentifier"="com.tinyspeck.slackmacgap"
# "LSDisplayName"="Slack"
# "StatusLabel"={ "label"="3" }
app_badges() {
  [ -f "$APPS" ] || return
  local app info bundle name label
  local label_pattern='"StatusLabel"=[{] "label"="([^"]+)"' bundle_pattern='"CFBundleIdentifier"="([^"]+)"'
  local name_pattern='"LSDisplayName"="([^"]+)"'
  while IFS= read -r app; do
    info="$(lsappinfo info -only CFBundleIdentifier -only LSDisplayName -only StatusLabel "$app" 2>/dev/null)"
    [[ $info =~ $label_pattern ]] || continue
    label="${BASH_REMATCH[1]}"
    [[ $info =~ $bundle_pattern ]] || continue
    bundle="${BASH_REMATCH[1]}"
    name="$app"
    [[ $info =~ $name_pattern ]] && name="${BASH_REMATCH[1]}"
    printf '%s\t%s\t%s\n' "$bundle" "$name" "$label"
  done < <(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//; /^$/d' "$APPS")
}

# text_widths <text>... [$'\n' <text>...]...: for each group of texts, separated by a newline, the
# width in points of the widest in the rows' font (the default label font), 0 for an empty group.
# SketchyBar measures text only once it draws it, but the rows need a fixed width to line up the
# badges and the versions and to highlight the whole row
text_widths() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run(argv) {
  const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize('HelveticaNeue-Bold', 13), $.NSFontAttributeName)
  const widths = [0]
  for (const text of argv) {
    if (text === '\n') widths.push(0)
    else widths[widths.length - 1] = Math.max(widths[widths.length - 1], Math.ceil($(text).sizeWithAttributes(font).width))
  }
  return widths.join(' ')
}
EOF
}

# badge <count>: sets BADGE to the label of a badge in the bar. The digits are all the same width,
# so the padding that centers the number depends on how many
badge() {
  local width=$((DIGIT_WIDTH * ${#1} + 2 * BADGE_INSET))
  [ $width -lt $BADGE_WIDTH ] && width=$BADGE_WIDTH
  BADGE=(label="$1" label.width=$width label.padding_left=$(((width - DIGIT_WIDTH * ${#1}) / 2)))
}

# Rebuilds the badges and the popup rows from the badges of the apps and what check found, or hides
# them when both are empty. During an upgrade or a restart it keeps what busy shows
draw() {
  local bundles=() apps=() labels=() scripts=() unread=0 bundle app label digits

  # The crashes first, in a row like the ones of the apps, with the icon of Console, where it opens
  # their log, and the time of the last one, or its day if it wasn't today. Each counts one
  local crashes last
  crashes=$(grep -c . "$CRASHES" 2>/dev/null)
  if [ "${crashes:-0}" -gt 0 ]; then
    last=$(tail -1 "$CRASHES")
    label=$(date -r "$last" +%H:%M)
    [ "$(date -r "$last" +%F)" = "$(date +%F)" ] || label=$(date -r "$last" +%-d/%-m)
    app=$CRASHED
    [ "$crashes" -gt 1 ] && app="$crashes $CRASHED_MANY"
    bundles+=(com.apple.Console) apps+=("$app") labels+=("$label") scripts+=("$0 crash")
    unread=$crashes
  fi

  while IFS=$'\t' read -r bundle app label; do
    [ -n "$bundle" ] || continue
    bundles+=("$bundle") apps+=("$app") labels+=("$label") scripts+=("$0 open $bundle")
    # A badge without a number, e.g. the dot of Slack for unread channels, counts as one
    digits="${label//[^0-9]/}"
    unread=$((unread + ${digits:+10#}${digits:-1}))
  done <<< "$(app_badges)"

  local kinds=() names=() versions=() restart="" kind name installed new
  while read -r kind name installed new; do
    case "$kind" in
      # Casks add the build after a comma, e.g. 3.35.0,6S1r8a6kUrQ,a
      formula|cask) kinds+=("$kind") names+=("$name") versions+=("${installed%%,*} → ${new%%,*}") ;;
      restart) restart="$name" ;;
    esac
  done <<< "$(cat "$OUTDATED" 2>/dev/null)"

  local updates=${#names[@]} items=(--remove '/notification\.row\..*/')
  [ -n "$restart" ] && updates=$((updates + 1))
  if [ $unread -eq 0 ] && [ $updates -eq 0 ]; then
    sketchybar "${items[@]}" --set notification drawing=off popup.drawing=off \
                             --set notification_apps drawing=off --set notification_brew drawing=off
    return
  fi

  # All the rows are as wide as the widest one, with the badges and the versions in one column
  local short_names=("${names[@]##*/}") values=("${versions[@]}" "${labels[@]}") actions=()
  [ ${#names[@]} -gt 0 ] && values+=("$UPGRADING")
  [ -n "$restart" ] && actions+=("$RESTART" "$RESTARTING")
  [ ${#names[@]} -gt 1 ] && actions+=("$UPGRADE_ALL")
  local package_width app_width value_width action_width
  read -r package_width app_width value_width action_width <<< \
    "$(text_widths "${short_names[@]}" $'\n' "${apps[@]}" $'\n' "${values[@]}" $'\n' "${actions[@]}")"
  local app_column=0 package_column=0 width=0
  [ ${#apps[@]} -gt 0 ] && app_column=$((PADDING + APP_ICON + ICON_GAP + ${app_width:-0} + GAP))
  [ ${#names[@]} -gt 0 ] && package_column=$((PADDING + ${package_width:-0} + GAP))
  local name_width=$((app_column > package_column ? app_column : package_column))
  [ $name_width -gt 0 ] && width=$((name_width + ${value_width:-0} + PADDING))
  local action_row_width=$((PADDING + ${action_width:-0} + PADDING))
  [ ${#actions[@]} -gt 0 ] && [ $action_row_width -gt $width ] && width=$action_row_width

  # The rows are INSET from the edges, so the highlight doesn't touch them
  local row=(
    width=$width
    padding_left=$INSET
    padding_right=$INSET
    icon.drawing=on
    icon.font="Helvetica Neue:Bold:13.0"
    icon.color=$TEXT
    icon.padding_left=$PADDING
    icon.width=$name_width
    label.color=$SUBTEXT
    label.padding_left=0
    label.padding_right=$PADDING
    # The hover changes the color: SketchyBar doesn't redraw a popup row for background.drawing
    background.color=$TRANSPARENT
    background.corner_radius=6
    background.height=24
    background.drawing=on
  )
  # "Riavvia AeroSpace" and "Aggiorna tutto" have no name column
  local action=("${row[@]}" icon.drawing=off label.color=$PRIMARY label.padding_left=$PADDING)
  # Room above the first row and below the last one, as in apple.sh, and between the apps and the
  # packages
  local space=(width=$width padding_left=$INSET padding_right=$INSET icon.drawing=off label.drawing=off
               background.drawing=on background.color=$TRANSPARENT background.height=4)
  items+=(--add item notification.row.top popup.notification --set notification.row.top "${space[@]}")

  # The name of an app after its icon, which is the background of the name
  local item i
  for ((i = 0; i < ${#apps[@]}; i++)); do
    item="notification.row.app.$i"
    items+=(--add item "$item" popup.notification
            --set "$item" "${row[@]}" icon="${apps[i]}" icon.padding_left=$((PADDING + APP_ICON + ICON_GAP))
                  icon.background.drawing=on icon.background.image="app.${bundles[i]}"
                  icon.background.image.scale=0.5 icon.background.image.padding_left=$PADDING
                  label="${labels[i]}" script="${scripts[i]}"
            --subscribe "$item" mouse.entered mouse.exited mouse.clicked)
  done
  if [ ${#apps[@]} -gt 0 ] && [ $updates -gt 0 ]; then
    items+=(--add item notification.row.gap popup.notification
            --set notification.row.gap "${space[@]}" background.height=$SECTION_GAP)
  fi

  if [ -n "$restart" ]; then
    items+=(--add item notification.row.brew.restart popup.notification
            --set notification.row.brew.restart "${action[@]}" label="$RESTART" script="$0 restart"
            --subscribe notification.row.brew.restart mouse.entered mouse.exited mouse.clicked)
  fi

  local all=()
  for ((i = 0; i < ${#names[@]}; i++)); do
    item="notification.row.brew.${kinds[i]}.${short_names[i]}"
    items+=(--add item "$item" popup.notification
            --set "$item" "${row[@]}" icon="${short_names[i]}" label="${versions[i]}"
                  script="$0 ${kinds[i]} ${names[i]}"
            --subscribe "$item" mouse.entered mouse.exited mouse.clicked)
    all+=("${kinds[i]}" "${names[i]}")
  done

  if [ ${#names[@]} -gt 1 ]; then
    items+=(--add item notification.row.brew.all popup.notification
            --set notification.row.brew.all "${action[@]}" label="$UPGRADE_ALL" script="$0 ${all[*]}"
            --subscribe notification.row.brew.all mouse.entered mouse.exited mouse.clicked)
  fi
  items+=(--add item notification.row.bottom popup.notification --set notification.row.bottom "${space[@]}")

  # The red badge is next to the green one, or 8 from the clock as the other components
  items+=(--set notification drawing=on)
  if [ $unread -gt 0 ]; then
    badge $unread
    items+=(--set notification_apps drawing=on "${BADGE[@]}")
  else
    items+=(--set notification_apps drawing=off)
  fi
  if [ $updates -gt 0 ]; then
    badge $updates
    local gap=8
    [ $unread -gt 0 ] && gap=$BADGE_GAP
    items+=(--set notification_brew drawing=on "${BADGE[@]}" padding_left=$gap background.color=$RED)
  else
    items+=(--set notification_brew drawing=off)
  fi

  # During an upgrade or a restart the red badge is yellow and the rows of brew are dimmed, except
  # the ones busy saved, which show its label
  local busy_label busy_row
  if locked && [ -f "$BUSY" ]; then
    {
      read -r busy_label
      items+=(--set notification_brew background.color=$YELLOW
              --set '/notification\.row\.brew\..*/' icon.color=$OVERLAY label.color=$OVERLAY)
      while read -r busy_row; do
        items+=(--set "$busy_row" label="$busy_label" label.color=$YELLOW)
      done
    } < "$BUSY"
  fi
  sketchybar "${items[@]}"
}

# One render at a time, since watch and check start theirs on their own: the later one reads the
# newer data. Its lock holds the pid of the job, as the one of lock
render() {
  local i
  for ((i = 0; i < 50; i++)); do
    if shlock -f "$RENDER_LOCK" -p "$(exec sh -c 'echo $PPID')"; then
      draw
      rm -f "$RENDER_LOCK"
      return
    fi
    sleep 0.1
  done
  draw
}

locked() {
  [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null
}

# One upgrade or restart at a time, the clicks meanwhile are ignored.
# The lock holds the pid of the background job, which bash 3.2 has no $BASHPID for
lock() {
  shlock -f "$LOCK" -p "$(exec sh -c 'echo $PPID')"
}

# busy <label> <row>...: during an upgrade or a restart the red badge turns yellow and the rows of
# brew are dimmed, except the given ones, which show the label. Saved, so that the renders while
# the lock is held, e.g. for the badges of the apps, keep it
busy() {
  printf '%s\n' "$@" > "$BUSY"
  render
}

# notify <group> <title> <message> <command run on click>: it replaces the notification of the
# same group. The command runs without the shell's PATH
notify() {
  terminal-notifier -group "$1" -title "$2" -message "$3" -execute "$4" > /dev/null
}

check() {
  # The upgrade or restart in progress refreshes the list when it is done
  locked && return
  # brew_update comes after an upgrade: only the installed versions changed
  [ "$SENDER" = "brew_update" ] || brew update > /dev/null 2>&1
  local version
  {
    outdated_packages
    version="$(aerospace_restart_version)" && echo "restart $version"
  } > "$OUTDATED.$$"
  mv "$OUTDATED.$$" "$OUTDATED"
  render
}

# A daemon keeps running the old version after an upgrade: restart it the way AeroSpace starts it
# at login, running its after-startup-command lines in aerospace.toml all at once. SketchyBar
# starts again by itself, since ../start.sh starts it again whenever it exits: its lines only
# reload it
restart_daemon() {
  pgrep -qx "$1" || return
  local config commands command i
  config="$(aerospace config --config-path)" || return
  commands="$(sed -nE "s/^[[:space:]]*'exec-and-forget ($1( .*)?)',?$/\1/p" "$config")"
  [ -n "$commands" ] || return

  # The new one starts once the old one is gone
  pkill -x "$1"
  for i in {1..25}; do
    pgrep -qx "$1" || break
    sleep 0.2
  done
  while IFS= read -r command; do
    bash -c "$command" > /dev/null 2>&1 &
  done <<< "$commands"
}

# Upgrades the <formula|cask> <name> pairs one at a time, then restarts the upgraded daemons
upgrade() {
  lock || return
  local packages=("$@") rows=() upgraded=() failed=() short version i
  for ((i = 0; i < ${#packages[@]}; i += 2)); do
    rows+=("notification.row.brew.${packages[i]}.${packages[i+1]##*/}")
  done
  busy "$UPGRADING" "${rows[@]}"

  exec > "$LOG" 2>&1
  for ((i = 0; i < ${#packages[@]}; i += 2)); do
    short="${packages[i+1]##*/}"
    if brew upgrade --"${packages[i]}" "${packages[i+1]}"; then
      upgraded+=("$short")
    else
      failed+=("$short")
    fi
  done
  rm -f "$LOCK" "$BUSY"

  if [ ${#failed[@]} -gt 0 ]; then
    notify sketchybar-brew-failed "Aggiornamento non riuscito: ${failed[*]}" \
           "Fai clic per vedere l'output di brew" "open '$LOG'"
  else
    terminal-notifier -remove sketchybar-brew-failed > /dev/null 2>&1
  fi
  for short in "${upgraded[@]}"; do
    restart_daemon "$short"
  done
  version="$(aerospace_restart_version)"
  if [[ " ${upgraded[*]} " == *" aerospace "* ]] && [ -n "$version" ]; then
    notify sketchybar-brew-aerospace "AeroSpace aggiornato alla $version" \
           "Riavvialo per usarla: fai clic per aprire il menu" \
           "$(command -v sketchybar) --set notification popup.drawing=on"
  fi
  sketchybar --trigger brew_update
}

# Restarts AeroSpace on the installed version. It puts the windows of the hidden workspaces back
# on screen only when quit from its own menu, and disabling it does the same: so it is disabled,
# killed and reopened. At startup it gives each window the workspace shown on its monitor, then
# the on-window-detected rules move their apps as usual
restart_aerospace() {
  lock || return
  busy "$RESTARTING" notification.row.brew.restart
  local i

  aerospace enable off > /dev/null 2>&1
  sleep 1
  pkill -x AeroSpace
  for i in {1..25}; do
    pgrep -qx AeroSpace || break
    sleep 0.2
  done
  open -a AeroSpace
  # Until the new one answers, aerospace --version can't tell which version it runs
  for i in {1..50}; do
    [ -n "$(aerospace_versions | cut -sd' ' -f2)" ] && break
    sleep 0.2
  done

  terminal-notifier -remove sketchybar-brew-aerospace > /dev/null 2>&1
  rm -f "$LOCK" "$BUSY"
  sketchybar --trigger brew_update
}

# watch: triggers notification_change whenever the badges of the apps or the crashes change. A
# reload of SketchyBar starts a new one and stops the old one
watch() {
  trap 'pkill -P $$; exit 0' TERM INT HUP
  local badges last
  while :; do
    badges="$(app_badges; cat "$CRASHES" 2>/dev/null)"
    if [ "$badges" != "$last" ]; then
      sketchybar --trigger notification_change
      last="$badges"
    fi
    sleep $POLL &
    wait $!
  done
}

if [ "$1" = watch ]; then
  watch
  exit 0
fi

# A popup row: crash, open, restart, or the packages it upgrades. The rows of brew ignore the mouse
# during an upgrade or a restart
if [ $# -gt 0 ]; then
  case "$SENDER" in
    mouse.entered) { [ "$1" = crash ] || [ "$1" = open ] || ! locked; } && sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked)
      case "$1" in
        # The crashes are seen once their log is open
        crash)
          sketchybar --set notification popup.drawing=off
          rm -f "$CRASHES"
          open -a Console "$CRASH_LOG"
          render
          ;;
        open)
          sketchybar --set notification popup.drawing=off
          open -b "$2"
          ;;
        restart) restart_aerospace & ;;
        *) upgrade "$@" & ;;
      esac
      ;;
  esac
  exit 0
fi

# The badges open the popup with their click_script
case "$SENDER" in
  mouse.exited.global) sketchybar --set notification popup.drawing=off ;;
  notification_change) render ;;
  *) check & ;;
esac
