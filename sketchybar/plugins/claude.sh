#!/usr/bin/env bash

# Claude plan usage: the claude item shows how much of the 5-hour session and of the weekly limit
# is used. Its popup has the account, a bar and the time left to the reset for each limit and the
# row that logs out, or only the one that logs in when no account is logged in.
# Claude Code reads them: claude -p answers the get_usage control request (the data of /usage)
# without sending any message, and renews the login when it has expired.
# The item runs this with no arguments, the popup rows with login or logout and their account.
# SketchyBar kills its scripts after 60 seconds, so the login, which waits for the browser, runs in
# the background.
# One item per account (see sketchybarrc): claude is the one of ~/.claude, claude_2, claude_3... those
# of claude_accounts.conf, whose Claude Code runs with the config dir of the account
# (CLAUDE_CONFIG_DIR). With more than one account there is also claude_all, for the displays where
# they would make the bar too long: it shows the account with the busiest session, and its popup all
# of them, one after the other. The rows of a popup are <item>.row.<name>, and in that of claude_all
# <item>.row.<account>.<name>. The items of the accounts and claude_all are on different displays,
# and both refresh: each account saves its data in TMPDIR, which the other reuses for a minute

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/claude_accounts.conf" 2> /dev/null

ITEM="${NAME%%.row.*}"
LOCK="${TMPDIR:-/tmp}/sketchybar_$ITEM.lock"
CLAUDE_ORANGE=0xffd97757
MAX_AGE=60  # seconds for which the data of an account is reused

WARNING=75   # from this percentage a limit turns yellow
CRITICAL=90  # and from this one red

FONT="Helvetica Neue:Bold:13.0"  # the default label font
SMALL_FONT="Helvetica Neue:Medium:11.0"
MIN_WIDTH=260
INSET=4          # between the rows and the edge of the popup, as in apple.sh
PADDING=8        # inside the rows
GAP=16           # between the two columns of a row
ROW_HEIGHT=24    # of a row of text, unless it sets its own
LIMIT_HEIGHT=34  # of the title of a limit, or of the message in its place, with room above
BAR_HEIGHT=6
DAYS=(lun mar mer gio ven sab dom)

UPDATING="Aggiornamento…"
LOGIN="Accedi"
LOGGING_IN="Accedi nel browser…"
LOGOUT="Esci"
CONFIRM_LOGOUT="Fai clic di nuovo per uscire"
NO_ACCOUNT="Nessun account"
LOGIN_HINT="Accedi per vedere quanto hai usato Claude"
SESSION="Sessione (5 ore)"

# use_account <n>: Claude Code runs with account n, 1 the one of ~/.claude, 2, 3... those of
# claude_accounts.conf. Sets ACCENT, its color, ICON, its icon (see sketchybarrc), DIR_TEXT, its
# config dir if not ~/.claude, and the files of its data, of its login and of the output of claude.
# Fails when there is no such account
use_account() {
  local color dir
  if [ "$1" = 1 ]; then
    unset CLAUDE_CONFIG_DIR
    ACCENT=$CLAUDE_ORANGE
    ICON="$CONFIG_DIR/helpers/claude_icon.png"
    DIR_TEXT=""
    LOG="$HOME/Library/Logs/sketchybar-claude.log"
  else
    read -r color dir <<< "${CLAUDE_ACCOUNTS[$1 - 2]}" 2> /dev/null
    [ -n "$dir" ] || return 1
    export CLAUDE_CONFIG_DIR="$dir"
    ACCENT=0xff$color
    ICON="$CONFIG_DIR/helpers/claude_icon_$color.png"
    case "$dir" in
      "$HOME"/*) DIR_TEXT="~${dir#"$HOME"}" ;;
      *) DIR_TEXT="$dir" ;;
    esac
    LOG="$HOME/Library/Logs/sketchybar-claude-$1.log"
  fi
  DATA="${TMPDIR:-/tmp}/sketchybar_claude_$1.data"
  LOGIN_LOCK="${TMPDIR:-/tmp}/sketchybar_claude_$1_login.lock"
}

# SketchyBar started at login has only the system PATH: also look where the installers put claude
find_claude() {
  local candidate
  for candidate in "$(command -v claude)" "$HOME/.local/bin/claude" /opt/homebrew/bin/claude \
                   /usr/local/bin/claude "$HOME"/.nvm/versions/node/*/bin/claude; do
    [ -x "$candidate" ] && echo "$candidate" && return
  done
  return 1
}

# <logged in> <email> <organization> <plan>, separated by \x1f since the fields can be empty
account() {
  "$CLAUDE" auth status --json 2>/dev/null |
    jq -r '[.loggedIn, .email // "", .orgName // "", .subscriptionType // ""] | join("\u001f")'
}

# The name of the account, which only Claude Code's own config has, in its config dir if not ~
display_name() {
  jq -r '.oauthAccount | .displayName // .fullName // empty' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null
}

# "<percent> <reset>" of the session, then of the week; the reset is a Unix time, or - when the
# window has not started yet. "none" when the login has no plan limits (e.g. an API key), nothing
# when Claude Code can't read them.
# Only what the answer needs: no CLAUDE.md, plugins, hooks or MCP servers, no transcript on disk,
# no telemetry or update check. Not CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, which skips the
# request too and answers with the last numbers saved in ~/.claude.json, up to an hour old; without
# it Claude Code asks the server when they are more than a minute old.
# perl's alarm stops claude if it hangs
usage() {
  printf '%s\n' '{"type":"control_request","request_id":"usage","request":{"subtype":"get_usage","skip_behaviors":true}}' |
    (cd "$HOME" && DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
       perl -e 'alarm shift; exec @ARGV' 30 \
       "$CLAUDE" -p --safe-mode --strict-mcp-config --no-session-persistence \
                 --input-format stream-json --output-format stream-json --verbose 2>/dev/null) |
    jq -r '
      def window: [(.utilization // 0 | round),
                   (.resets_at // "" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
                    | if . == "" then "-" else fromdateiso8601 end)];
      select(.type == "control_response" and .response.request_id == "usage") | .response.response
      | if .rate_limits_available == false then "none"
        elif .rate_limits then [(.rate_limits.five_hour | window), (.rate_limits.seven_day | window)]
                               | flatten | join(" ")
        else empty end'
}

# read_account: the data of the account in use, from Claude Code, separated by \x1f: <logged in>
# <email> <organization> <plan> <name> <session percent> <session reset> <week percent> <week reset>
# <stale>. A reading that fails, e.g. on wake before the network is back, keeps the last numbers of
# the account, stale
read_account() {
  local logged_in email organization plan name session session_reset week week_reset stale="" old=()
  IFS=$'\x1f' read -r logged_in email organization plan <<< "$(account)"
  [ "$logged_in" != true ] && echo false && return
  name="$(display_name)"
  read -r session session_reset week week_reset <<< "$(usage)"
  [ -f "$DATA" ] && IFS=$'\x1f' read -r -a old < "$DATA"
  if [ -z "$session" ] && [ "${old[1]}" = "$email" ] && [ -n "${old[5]}" ]; then
    session=${old[5]} session_reset=${old[6]} week=${old[7]} week_reset=${old[8]} stale=1
  fi
  local IFS=$'\x1f'
  local fields=(true "$email" "$organization" "$plan" "$name" "$session" "$session_reset" "$week"
                "$week_reset" "$stale")
  echo "${fields[*]}"
}

# fetch: the data of the account in use, saved when it is at most MAX_AGE seconds old or another
# refresh is reading it, which this waits for
fetch() {
  local i
  if [ ! -f "$DATA" ] || [ $(($(date +%s) - $(stat -f %m "$DATA"))) -gt $MAX_AGE ]; then
    if lock "$DATA.lock"; then
      read_account > "$DATA.$$" && mv "$DATA.$$" "$DATA"
      rm -f "$DATA.lock"
    else
      for ((i = 0; i < 250; i++)); do
        kill -0 "$(cat "$DATA.lock" 2>/dev/null)" 2>/dev/null || break
        sleep 0.2
      done
    fi
  fi
  cat "$DATA" 2>/dev/null
}

# Width in points of the widest text in the font, e.g. text_width HelveticaNeue-Bold 13 <text>...
# SketchyBar measures text only once it draws it, but the rows need a fixed width to line up the
# right column and the bars
text_width() {
  osascript -l JavaScript - "$@" <<'EOF'
ObjC.import('AppKit')
function run([name, size, ...texts]) {
  const font = $.NSDictionary.dictionaryWithObjectForKey($.NSFont.fontWithNameSize(name, Number(size)), $.NSFontAttributeName)
  return Math.max(0, ...texts.map(text => Math.ceil($(text).sizeWithAttributes(font).width)))
}
EOF
}

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

# "Reset tra 2 h 57 min · 01:10", with the day when it is more than a day away
reset_text() {
  [ "$1" = "-" ] && echo "Parte con il prossimo messaggio" && return
  local left=$(($1 - $(date +%s))) at
  at="$(date -r "$1" +%H:%M)"
  if [ $left -ge 86400 ]; then
    echo "Reset tra $((left / 86400)) g $((left % 86400 / 3600)) h · ${DAYS[$(date -r "$1" +%u) - 1]} $at"
  elif [ $left -ge 3600 ]; then
    echo "Reset tra $((left / 3600)) h $((left % 3600 / 60)) min · $at"
  elif [ $left -ge 60 ]; then
    echo "Reset tra $((left / 60)) min · $at"
  else
    echo "Reset tra meno di un minuto"
  fi
}

# Each refresh lists all the popup rows: row <name> <properties>... puts one at the bottom.
# names, adds and sets are the rows, the commands that add them and the ones that set them. The
# names start with PREFIX, the account in the popup of claude_all.
# The rows are INSET from the edges, so the highlight doesn't touch them
names=() adds=() sets=() PREFIX=""
row() {
  local name="$ITEM.row.$PREFIX$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" "popup.$ITEM")
  sets+=(--set "$name" padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
}

# separator <name>: the line between the accounts in the popup of claude_all, as in apple.sh
separator() {
  row "$1" icon.drawing=on icon="" icon.width=$((WIDTH - 2 * PADDING)) \
           icon.padding_left=0 icon.padding_right=0 icon.background.drawing=on \
           icon.background.color=$SURFACE icon.background.height=1 label.drawing=off \
           background.drawing=on background.color=$TRANSPARENT background.height=11
  sets+=(padding_left=$((INSET + PADDING)) width=$((WIDTH - 2 * PADDING)))
}

# A row with a text on the left and, if given, one on the right: the widths are set by layout.
# A row is as tall as its background, and SketchyBar draws it in a window of that height which
# clips what is out of it: the texts stay centered and the rows that need more room above or less
# add background.height
# text_row <name> <left> <left font> <left color> [<right> <right font> <right color>]
text_row() {
  local properties=(width=$WIDTH icon.drawing=on icon="$2" icon.font="$3" icon.color=$4
                    icon.padding_left=$PADDING icon.padding_right=0 label.padding_left=0
                    background.drawing=on background.color=$TRANSPARENT
                    background.height=$ROW_HEIGHT)
  if [ -n "$5" ]; then
    # A fixed width includes the padding
    properties+=(icon.width=$((WIDTH - RIGHT_WIDTH - PADDING))
                 label="$5" label.font="$6" label.color=$7 label.width=$((RIGHT_WIDTH + PADDING))
                 label.align=right label.padding_right=$PADDING)
  else
    properties+=(label.drawing=off)
  fi
  row "$1" "${properties[@]}"
}

# A bar filled for the percentage: the fill is the background of an empty icon as wide as the
# percentage, over the background of the row
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

# limit_rows <name> <title> <percent> <reset text>: the title with the percentage, the bar and the
# reset. The title is taller, which parts the limits, and the bar row is only the bar
limit_rows() {
  text_row "$1" "$2" "$FONT" $TEXT "$3%" "$FONT" "$(color_for "$3" $TEXT)"
  sets+=(background.height=$LIMIT_HEIGHT)
  bar_row "$1.bar" "$3" "$(color_for "$3" $ACCENT)"
  text_row "$1.reset" "$4" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=30)
}

# action_row <login|logout> <text>: the row lights up under the mouse and runs this on click, with
# the account of the section
action_row() {
  row "$1" width=$WIDTH icon.drawing=on icon="$2" icon.font="$FONT" icon.color=$PRIMARY \
           icon.padding_left=$PADDING label.drawing=off script="$0 $1 $SECTION" \
           background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
           background.height=$ROW_HEIGHT
  sets+=(--subscribe "$ITEM.row.$PREFIX$1" mouse.entered mouse.exited mouse.clicked)
}

# layout <right column texts> -- <other texts, SMALL_FONT>: WIDTH fits the widest row, RIGHT_WIDTH
# the widest text of the right column. The left column is the name of the accounts (NAME_TEXTS) and
# the titles of the limits
layout() {
  local right=() small=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do right+=("$1"); shift; done
  shift
  small=("$@")
  RIGHT_WIDTH=$(text_width HelveticaNeue-Bold 13 "${right[@]}")
  WIDTH=$((PADDING + $(text_width HelveticaNeue-Bold 13 "${NAME_TEXTS[@]}" "$SESSION") + GAP + RIGHT_WIDTH + PADDING))
  local small_width=$((PADDING + $(text_width HelveticaNeue-Medium 11 "${small[@]}") + PADDING))
  [ $small_width -gt $WIDTH ] && WIDTH=$small_width
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))
}

# show <properties of the item>...: sets the popup rows, and removes and adds them only when they
# aren't the ones already there. The click that opens the popup refreshes it, and removing the row
# under the mouse would close it (mouse.exited.global)
show() {
  space bottom 4
  if [ "$(sketchybar --query "$ITEM" | jq -r --arg keep "keep.$ITEM" '.popup.items // [] | . - [$keep] | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" --set "$ITEM" "$@"
  else
    sketchybar --remove "/$ITEM\.row\..*/" "${adds[@]}" "${sets[@]}" --set "$ITEM" "$@"
  fi
}

# prepare <n> <data, as read_account>: what the section of account n shows, in arrays by account:
# its STATE (logged_out, ok, none when the login has no plan limits, failed when Claude Code can't
# read them), its name and the details under it, its plan, the percentages and the times to the
# resets, the hour of the reset of the session, and the label of the item, dimmed when the numbers
# are stale. Adds the texts to layout's
prepare() {
  local logged_in email organization plan name session session_reset week week_reset stale details
  IFS=$'\x1f' read -r logged_in email organization plan name session session_reset week week_reset stale <<< "$2"
  use_account "$1"
  LABEL[$1]="" LABEL_COLOR[$1]=$TEXT SESSION_AT[$1]=""
  if [ "$logged_in" != true ]; then
    STATE[$1]=logged_out NAME_TEXT[$1]="$NO_ACCOUNT" DETAILS[$1]="$DIR_TEXT"
    NAME_TEXTS+=("$NO_ACCOUNT") SMALL_TEXTS+=("$LOGIN_HINT" "$DIR_TEXT")
    return
  fi
  # "team" → "Claude Team"
  [ -n "$plan" ] && plan="Claude $(tr '[:lower:]' '[:upper:]' <<< "${plan:0:1}")${plan:1}"
  details="$email"
  [ -n "$name" ] || details=""
  [ -n "$organization" ] && details="${details:+$details · }$organization"
  NAME_TEXT[$1]="${name:-$email}" DETAILS[$1]="$details" PLAN[$1]="$plan"
  NAME_TEXTS+=("${NAME_TEXT[$1]}") RIGHT_TEXTS+=("$plan") SMALL_TEXTS+=("$details")
  case "$session" in
    none) STATE[$1]=none ;;
    "") STATE[$1]=failed ;;
    *)
      STATE[$1]=ok SESSION_PERCENT[$1]=$session WEEK_PERCENT[$1]=$week
      SESSION_TEXT[$1]="$(reset_text "$session_reset")" WEEK_TEXT[$1]="$(reset_text "$week_reset")"
      [ "$session_reset" != "-" ] && SESSION_AT[$1]="$(date -r "$session_reset" +%H:%M)"
      SMALL_TEXTS+=("${SESSION_TEXT[$1]}" "${WEEK_TEXT[$1]}")
      LABEL[$1]="$session% · $week%"
      if [ -n "$stale" ]; then
        LABEL_COLOR[$1]=$OVERLAY
      else
        LABEL_COLOR[$1]=$(color_for $((session > week ? session : week)) $TEXT)
      fi
      ;;
  esac
}

# section <n> <name color>: the rows of account n, as prepared, under its name in that color
section() {
  SECTION=$1
  use_account "$1"
  if [ "${STATE[$1]}" = logged_out ]; then
    text_row status "$NO_ACCOUNT" "$FONT" $2
    [ -n "${DETAILS[$1]}" ] && text_row details "${DETAILS[$1]}" "$SMALL_FONT" $SUBTEXT && sets+=(background.height=16)
    text_row hint "$LOGIN_HINT" "$SMALL_FONT" $SUBTEXT
    if [ -f "$LOGIN_LOCK" ] && kill -0 "$(cat "$LOGIN_LOCK")" 2>/dev/null; then
      action_row login "$LOGGING_IN"
      sets+=(--set "$ITEM.row.${PREFIX}login" icon.color=$YELLOW)
    else
      action_row login "$LOGIN"
    fi
    return
  fi
  text_row account "${NAME_TEXT[$1]}" "$FONT" $2 "${PLAN[$1]}" "$SMALL_FONT" $SUBTEXT
  # Close to the name, which leaves more room before the limits
  [ -n "${DETAILS[$1]}" ] && text_row details "${DETAILS[$1]}" "$SMALL_FONT" $SUBTEXT && sets+=(background.height=16)
  case "${STATE[$1]}" in
    # The message in place of the limits
    none | failed)
      local message="Il tuo account non ha limiti del piano"
      [ "${STATE[$1]}" = failed ] && message="Impossibile leggere l'uso di Claude"
      text_row status "$message" "$FONT" $YELLOW
      sets+=(background.height=$LIMIT_HEIGHT)
      ;;
    ok)
      limit_rows session "$SESSION" "${SESSION_PERCENT[$1]}" "${SESSION_TEXT[$1]}"
      limit_rows week "Settimanale" "${WEEK_PERCENT[$1]}" "${WEEK_TEXT[$1]}"
      ;;
  esac
  action_row logout "$LOGOUT"
}

# refresh [wait]: a click waits for the refresh in progress, which may have read the numbers before
# it, the others leave it to that one
refresh() {
  until lock "$LOCK"; do
    [ "$1" = "wait" ] || return
    sleep 0.2
  done
  NAME_TEXTS=() RIGHT_TEXTS=() SMALL_TEXTS=()
  if ! CLAUDE="$(find_claude)"; then
    NAME_TEXTS=("Claude Code non trovato")
    layout --
    space top 4
    text_row status "${NAME_TEXTS[0]}" "$FONT" $RED
    show label=""
    rm -f "$LOCK"
    return
  fi

  # The accounts of the item, read at the same time
  local accounts=() n data top
  case "$ITEM" in
    claude) accounts=(1) ;;
    claude_all) for ((n = 1; n <= 1 + ${#CLAUDE_ACCOUNTS[@]}; n++)); do accounts+=($n); done ;;
    *) accounts=("${ITEM#claude_}") ;;
  esac
  data="$(mktemp -d)"
  for n in "${accounts[@]}"; do
    (use_account $n && fetch > "$data/$n") &
  done
  wait
  for n in "${accounts[@]}"; do
    [ -f "$data/$n" ] && prepare $n "$(cat "$data/$n")"
  done
  rm -rf "$data"

  if [ -z "${STATE[${accounts[0]}]}" ]; then
    rm -f "$LOCK"
    return
  fi
  layout "${RIGHT_TEXTS[@]}" "100%" "$UPDATING" -- "${SMALL_TEXTS[@]}"
  space top 4
  if [ "$ITEM" != claude_all ]; then
    n=${accounts[0]}
    section $n $TEXT
    # With more than one account the item is only on the large displays (see notch.sh), which have
    # room for the hour of the reset of the session: "42% · 31% · 17:07"
    local label="${LABEL[$n]}"
    [ ${#CLAUDE_ACCOUNTS[@]} -gt 0 ] && [ -n "${SESSION_AT[$n]}" ] && label="$label · ${SESSION_AT[$n]}"
    show label="$label" label.color=${LABEL_COLOR[$n]}
    rm -f "$LOCK"
    return
  fi

  # claude_all: every account, under its name in its color, and in the bar the one with the
  # busiest session, with its icon. The first one at a tie, and without any numbers
  top=1
  for n in "${accounts[@]}"; do
    [ "${STATE[$n]}" = ok ] || continue
    if [ "${STATE[$top]}" != ok ] || [ "${SESSION_PERCENT[$n]}" -gt "${SESSION_PERCENT[$top]}" ]; then
      top=$n
    fi
  done
  for n in "${accounts[@]}"; do
    [ -n "${STATE[$n]}" ] || continue
    [ $n -gt 1 ] && PREFIX="" && separator "$n.separator"
    PREFIX="$n."
    use_account $n
    section $n $ACCENT
  done
  PREFIX=""
  use_account $top
  local icon=(icon.color=$ACCENT)
  [ -f "$ICON" ] && icon=(icon.background.image="$ICON")
  show label="${LABEL[$top]}" label.color=${LABEL_COLOR[$top]} "${icon[@]}"
  rm -f "$LOCK"
}

# The lock holds the pid of the background job, which bash 3.2 has no $BASHPID for
lock() {
  shlock -f "$1" -p "$(exec sh -c 'echo $PPID')"
}

# notify <title>: a click opens the output of claude. The command runs without the shell's PATH
notify() {
  terminal-notifier -group "sketchybar-claude-$SECTION" -title "$1" -message "Fai clic per vedere l'output di claude" \
                    -execute "open '$LOG'" > /dev/null
}

# claude opens the sign-in page in the browser and waits for it to send back the code; after
# 5 minutes it is stopped. The data of the account is read again
login() {
  lock "$LOGIN_LOCK" || return
  sketchybar --set "$NAME" icon="$LOGGING_IN" icon.color=$YELLOW
  perl -e 'alarm shift; exec @ARGV' 300 "$CLAUDE" auth login < /dev/null > "$LOG" 2>&1 ||
    notify "Accesso a Claude non riuscito"
  rm -f "$LOGIN_LOCK" "$DATA"
  sketchybar --trigger claude_update
}

logout() {
  "$CLAUDE" auth logout > "$LOG" 2>&1 || notify "Uscita da Claude non riuscita"
  rm -f "$DATA"
  sketchybar --trigger claude_update
}

# A popup row: login, or logout, which asks for a second click, of the account after it
if [ "$NAME" != "$ITEM" ]; then
  SECTION=$2
  use_account "$2" || exit 0
  CLAUDE="$(find_claude)" || exit 0
  case "$SENDER:$1" in
    mouse.entered:*) sketchybar --set "$NAME" background.color=$HIGHLIGHT ;;
    mouse.exited:logout) sketchybar --set "$NAME" background.color=$TRANSPARENT icon="$LOGOUT" icon.color=$PRIMARY ;;
    mouse.exited:*) sketchybar --set "$NAME" background.color=$TRANSPARENT ;;
    mouse.clicked:login) login & ;;
    mouse.clicked:logout)
      if [ "$(sketchybar --query "$NAME" | jq -r .icon.value)" = "$CONFIRM_LOGOUT" ]; then
        sketchybar --set "$NAME" icon="$LOGOUT" icon.color=$PRIMARY
        logout &
      else
        sketchybar --set "$NAME" icon="$CONFIRM_LOGOUT" icon.color=$RED
      fi
      ;;
  esac
  exit 0
fi

case "$SENDER" in
  # Every click refreshes the numbers and the times to the reset; until they arrive the right of
  # the account rows says so (without an account there is no such row)
  mouse.clicked)
    sketchybar --set "$ITEM" popup.drawing=toggle
    sketchybar --set "/$ITEM\.row\..*account/" label="$UPDATING" > /dev/null 2>&1
    refresh wait &
    ;;
  mouse.exited.global) sketchybar --set "$ITEM" popup.drawing=off ;;
  *) refresh & ;;
esac
