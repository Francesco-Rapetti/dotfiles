#!/usr/bin/env bash

# Updates for the Homebrew packages in the Brewfile at the root of the dotfiles: the brew item is a
# badge with how many there are, and its popup lists them with the installed and the new version.
# A click on a row upgrades that package, "Aggiorna tutto" upgrades them all.
# AeroSpace keeps running the old version after an upgrade: until it restarts the popup also has
# "Riavvia AeroSpace", counted in the badge, and the notification of the upgrade opens the popup
# The brew item runs this with no arguments, each popup row with restart or with the
# <formula|cask> <name> pairs it upgrades. SketchyBar kills its scripts after 60 seconds, so brew
# runs in the background

BREWFILE="$CONFIG_DIR/../Brewfile"
LOCK="${TMPDIR:-/tmp}/sketchybar_brew.lock"
LOG="$HOME/Library/Logs/sketchybar-brew.log"

source "$CONFIG_DIR/colors.sh"

UPGRADING="aggiornamento…"
UPGRADE_ALL="Aggiorna tutto"
RESTART="Riavvia AeroSpace"
RESTARTING="Riavvio di AeroSpace…"
PADDING=8  # inside the rows
GAP=16     # between the name and the versions
BADGE_WIDTH=18  # label.width of the brew item in sketchybarrc
DIGIT_WIDTH=6   # every digit of the badge font, Helvetica Neue Bold 11

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

# Width in points of the widest of the arguments in the rows' font (the default label font).
# SketchyBar measures text only once it draws it, but the rows need a fixed width to line up the
# versions and to highlight the whole row
text_width() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run(argv) {
  const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize('HelveticaNeue-Bold', 13), $.NSFontAttributeName)
  return Math.max(...argv.map(text => Math.ceil($(text).sizeWithAttributes(font).width)))
}
EOF
}

# Rebuilds the popup rows and the badge from the output of outdated_packages and the output of
# aerospace_restart_version, or hides the item when both are empty
render() {
  local kinds=() names=() versions=() kind name installed new
  while read -r kind name installed new; do
    [ -n "$name" ] || continue
    # Casks add the build after a comma, e.g. 3.35.0,6S1r8a6kUrQ,a
    kinds+=("$kind") names+=("$name") versions+=("${installed%%,*} → ${new%%,*}")
  done <<< "$1"

  local count=${#names[@]} items=(--remove '/brew\.row\..*/')
  [ -n "$2" ] && count=$((count + 1))
  if [ $count -eq 0 ]; then
    sketchybar "${items[@]}" --set brew drawing=off popup.drawing=off
    return
  fi

  # All the rows are as wide as the widest one
  local short_names=("${names[@]##*/}") name_width=0 width=0 actions=()
  if [ ${#names[@]} -gt 0 ]; then
    name_width=$((PADDING + $(text_width "${short_names[@]}") + GAP))
    width=$((name_width + $(text_width "${versions[@]}" "$UPGRADING") + PADDING))
  fi
  [ -n "$2" ] && actions+=("$RESTART" "$RESTARTING")
  [ ${#names[@]} -gt 1 ] && actions+=("$UPGRADE_ALL")
  if [ ${#actions[@]} -gt 0 ]; then
    local action_width=$((PADDING + $(text_width "${actions[@]}") + PADDING))
    [ $action_width -gt $width ] && width=$action_width
  fi

  local row=(
    width=$width
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
  local action=("${row[@]}" label.color=$PRIMARY label.padding_left=$PADDING)

  if [ -n "$2" ]; then
    items+=(--add item brew.row.restart popup.brew
            --set brew.row.restart "${action[@]}" label="$RESTART" script="$0 restart"
            --subscribe brew.row.restart mouse.entered mouse.exited mouse.clicked)
  fi

  local all=() item i
  for ((i = 0; i < ${#names[@]}; i++)); do
    item="brew.row.${kinds[i]}.${short_names[i]}"
    items+=(--add item "$item" popup.brew
            --set "$item" "${row[@]}" icon.drawing=on icon="${short_names[i]}"
                  label="${versions[i]}" script="$0 ${kinds[i]} ${names[i]}"
            --subscribe "$item" mouse.entered mouse.exited mouse.clicked)
    all+=("${kinds[i]}" "${names[i]}")
  done

  if [ ${#names[@]} -gt 1 ]; then
    items+=(--add item brew.row.all popup.brew
            --set brew.row.all "${action[@]}" label="$UPGRADE_ALL" script="$0 ${all[*]}"
            --subscribe brew.row.all mouse.entered mouse.exited mouse.clicked)
  fi

  # The digits are all the same width, so the padding that centers the number depends on how many
  sketchybar "${items[@]}" --set brew drawing=on label=$count background.color=$RED \
                                      label.padding_left=$(((BADGE_WIDTH - DIGIT_WIDTH * ${#count}) / 2))
}

locked() {
  [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null
}

# One upgrade or restart at a time, the clicks meanwhile are ignored.
# The lock holds the pid of the background job, which bash 3.2 has no $BASHPID for
lock() {
  shlock -f "$LOCK" -p "$(exec sh -c 'echo $PPID')"
}

# busy <label> <row>...: during an upgrade or a restart the badge turns yellow and the rows are
# dimmed, except the given ones, which show the label
busy() {
  local label="$1" row
  local items=(--set brew background.color=$YELLOW
               --set '/brew\.row\..*/' icon.color=$OVERLAY label.color=$OVERLAY
                                     background.color=$TRANSPARENT)
  shift
  for row in "$@"; do
    items+=(--set "$row" label="$label" label.color=$YELLOW)
  done
  sketchybar "${items[@]}"
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
  render "$(outdated_packages)" "$(aerospace_restart_version)"
}

# A daemon keeps running the old version after an upgrade: restart it the way AeroSpace starts it
# at login, running its after-startup-command lines in aerospace.toml all at once
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
    rows+=("brew.row.${packages[i]}.${packages[i+1]##*/}")
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
  rm -f "$LOCK"

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
           "$(command -v sketchybar) --set brew popup.drawing=on"
  fi
  sketchybar --trigger brew_update
}

# Restarts AeroSpace on the installed version. It puts the windows of the hidden workspaces back
# on screen only when quit from its own menu, and disabling it does the same: so it is disabled,
# killed and reopened. At startup it gives each window the workspace shown on its monitor, then
# the on-window-detected rules move their apps as usual
restart_aerospace() {
  lock || return
  busy "$RESTARTING" brew.row.restart
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
  rm -f "$LOCK"
  sketchybar --trigger brew_update
}

# A popup row: restart, or the packages it upgrades
if [ "$NAME" != "brew" ]; then
  case "$SENDER" in
    mouse.entered) locked || sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked)
      if [ "$1" = "restart" ]; then
        restart_aerospace &
      else
        upgrade "$@" &
      fi
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  mouse.clicked) sketchybar --set brew popup.drawing=toggle ;;
  mouse.exited.global) sketchybar --set brew popup.drawing=off ;;
  *) check & ;;
esac
