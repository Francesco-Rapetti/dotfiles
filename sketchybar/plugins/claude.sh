#!/usr/bin/env bash

# Claude plan usage: the claude item shows how much of the 5-hour session and of the weekly limit
# is used. Its popup has the account, a bar and the time left to the reset for each limit and the
# row that logs out, or only the one that logs in when no account is logged in.
# Claude Code reads them: claude -p answers the get_usage control request (the data of /usage)
# without sending any message, and renews the login when it has expired.
# The item runs this with no arguments, the popup rows with login or logout. SketchyBar kills its
# scripts after 60 seconds, so the login, which waits for the browser, runs in the background

LOCK="${TMPDIR:-/tmp}/sketchybar_claude.lock"
LOGIN_LOCK="${TMPDIR:-/tmp}/sketchybar_claude_login.lock"
LOG="$HOME/Library/Logs/sketchybar-claude.log"

source "$CONFIG_DIR/colors.sh"
CLAUDE_ORANGE=0xffd97757

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

# The name of the account, which only Claude Code's own config has
display_name() {
  jq -r '.oauthAccount | .displayName // .fullName // empty' "$HOME/.claude.json" 2>/dev/null
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
# names, adds and sets are the rows, the commands that add them and the ones that set them.
# The rows are INSET from the edges, so the highlight doesn't touch them
names=() adds=() sets=()
row() {
  local name="claude.row.$1"
  shift
  names+=("$name")
  adds+=(--add item "$name" popup.claude)
  sets+=(--set "$name" padding_left=$INSET padding_right=$INSET "$@")
}

# space <name> <height>: room above the first row and below the last one, as in apple.sh
space() {
  row "$1" width=$WIDTH icon.drawing=off label.drawing=off background.drawing=on \
           background.color=$TRANSPARENT background.height=$2
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
  bar_row "$1.bar" "$3" "$(color_for "$3" $CLAUDE_ORANGE)"
  text_row "$1.reset" "$4" "$SMALL_FONT" $SUBTEXT
  sets+=(background.height=30)
}

# action_row <login|logout> <text>: the row lights up under the mouse and runs this on click
action_row() {
  row "$1" width=$WIDTH icon.drawing=on icon="$2" icon.font="$FONT" icon.color=$PRIMARY \
           icon.padding_left=$PADDING label.drawing=off script="$0 $1" \
           background.drawing=on background.color=$TRANSPARENT background.corner_radius=6 \
           background.height=$ROW_HEIGHT
  sets+=(--subscribe "claude.row.$1" mouse.entered mouse.exited mouse.clicked)
}

# layout <right column texts> -- <other texts, SMALL_FONT>: WIDTH fits the widest row, RIGHT_WIDTH
# the widest text of the right column
layout() {
  local right=() small=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do right+=("$1"); shift; done
  shift
  small=("$@")
  RIGHT_WIDTH=$(text_width HelveticaNeue-Bold 13 "${right[@]}")
  WIDTH=$((PADDING + $(text_width HelveticaNeue-Bold 13 "$NAME_TEXT" "Sessione (5 ore)") + GAP + RIGHT_WIDTH + PADDING))
  local small_width=$((PADDING + $(text_width HelveticaNeue-Medium 11 "${small[@]}") + PADDING))
  [ $small_width -gt $WIDTH ] && WIDTH=$small_width
  [ $((MIN_WIDTH - 2 * INSET)) -gt $WIDTH ] && WIDTH=$((MIN_WIDTH - 2 * INSET))
}

# show <properties of the claude item>...: sets the popup rows, and removes and adds them only
# when they aren't the ones already there. The click that opens the popup refreshes it, and
# removing the row under the mouse would close it (mouse.exited.global)
show() {
  space bottom 4
  if [ "$(sketchybar --query claude | jq -r '.popup.items | join(" ")')" = "${names[*]}" ]; then
    sketchybar "${sets[@]}" --set claude "$@"
  else
    sketchybar --remove '/claude\.row\..*/' "${adds[@]}" "${sets[@]}" --set claude "$@"
  fi
}

logged_out() {
  NAME_TEXT="Nessun account"
  layout -- "Accedi per vedere quanto hai usato Claude"
  space top 4
  text_row status "$NAME_TEXT" "$FONT" $TEXT
  text_row hint "Accedi per vedere quanto hai usato Claude" "$SMALL_FONT" $SUBTEXT
  if [ -f "$LOGIN_LOCK" ] && kill -0 "$(cat "$LOGIN_LOCK")" 2>/dev/null; then
    action_row login "$LOGGING_IN"
    sets+=(--set claude.row.login icon.color=$YELLOW)
  else
    action_row login "$LOGIN"
  fi
  show label=""
}

# problem <message>: the account rows stay, with the message in place of the limits
problem() {
  text_row status "$1" "$FONT" $YELLOW
  sets+=(background.height=$LIMIT_HEIGHT)
  action_row logout "$LOGOUT"
  show label=""
}

# refresh [wait]: a click waits for the refresh in progress, which may have read the numbers before
# it, the others leave it to that one
refresh() {
  until lock "$LOCK"; do
    [ "$1" = "wait" ] || return
    sleep 0.2
  done
  if ! CLAUDE="$(find_claude)"; then
    NAME_TEXT="Claude Code non trovato"
    layout --
    space top 4
    text_row status "$NAME_TEXT" "$FONT" $RED
    show label=""
    rm -f "$LOCK"
    return
  fi

  local logged_in email organization plan name
  IFS=$'\x1f' read -r logged_in email organization plan <<< "$(account)"
  if [ "$logged_in" != "true" ]; then
    logged_out
    rm -f "$LOCK"
    return
  fi

  # "team" → "Claude Team"
  [ -n "$plan" ] && plan="Claude $(tr '[:lower:]' '[:upper:]' <<< "${plan:0:1}")${plan:1}"
  local session_percent session_reset week_percent week_reset
  read -r session_percent session_reset week_percent week_reset <<< "$(usage)"
  # A refresh that fails, e.g. on wake before the network is back, keeps the last numbers, dimmed
  if [ -z "$session_percent" ] && sketchybar --query claude.row.session > /dev/null 2>&1; then
    sketchybar --set claude label.color=$OVERLAY --set claude.row.account label="$plan"
    rm -f "$LOCK"
    return
  fi

  name="$(display_name)"
  NAME_TEXT="${name:-$email}"
  local details="$email"
  [ -n "$name" ] || details=""
  [ -n "$organization" ] && details="${details:+$details · }$organization"
  local session_text week_text
  if [ "$session_percent" != "none" ] && [ -n "$session_percent" ]; then
    session_text="$(reset_text "$session_reset")" week_text="$(reset_text "$week_reset")"
  fi
  layout "$plan" "100%" "$UPDATING" -- "$details" "$session_text" "$week_text"
  space top 4

  text_row account "$NAME_TEXT" "$FONT" $TEXT "$plan" "$SMALL_FONT" $SUBTEXT
  # Close to the name, which leaves more room before the limits
  [ -n "$details" ] && text_row details "$details" "$SMALL_FONT" $SUBTEXT && sets+=(background.height=16)
  case "$session_percent" in
    none) problem "Il tuo account non ha limiti del piano" ;;
    "") problem "Impossibile leggere l'uso di Claude" ;;
    *)
      local label_color
      label_color=$(color_for $((session_percent > week_percent ? session_percent : week_percent)) $TEXT)
      limit_rows session "Sessione (5 ore)" "$session_percent" "$session_text"
      limit_rows week "Settimanale" "$week_percent" "$week_text"
      action_row logout "$LOGOUT"
      show label="$session_percent% · $week_percent%" label.color=$label_color
      ;;
  esac
  rm -f "$LOCK"
}

# The lock holds the pid of the background job, which bash 3.2 has no $BASHPID for
lock() {
  shlock -f "$1" -p "$(exec sh -c 'echo $PPID')"
}

# notify <title>: a click opens the output of claude. The command runs without the shell's PATH
notify() {
  terminal-notifier -group sketchybar-claude -title "$1" -message "Fai clic per vedere l'output di claude" \
                    -execute "open '$LOG'" > /dev/null
}

# claude opens the sign-in page in the browser and waits for it to send back the code; after
# 5 minutes it is stopped
login() {
  lock "$LOGIN_LOCK" || return
  sketchybar --set claude.row.login icon="$LOGGING_IN" icon.color=$YELLOW
  perl -e 'alarm shift; exec @ARGV' 300 "$CLAUDE" auth login < /dev/null > "$LOG" 2>&1 ||
    notify "Accesso a Claude non riuscito"
  rm -f "$LOGIN_LOCK"
  sketchybar --trigger claude_update
}

logout() {
  "$CLAUDE" auth logout > "$LOG" 2>&1 || notify "Uscita da Claude non riuscita"
  sketchybar --trigger claude_update
}

# A popup row: login, or logout, which asks for a second click
if [ "$NAME" != "claude" ]; then
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
  # the account row says so (without an account there is no such row)
  mouse.clicked)
    sketchybar --set claude popup.drawing=toggle
    sketchybar --set claude.row.account label="$UPDATING" > /dev/null 2>&1
    refresh wait &
    ;;
  mouse.exited.global) sketchybar --set claude popup.drawing=off ;;
  *) refresh & ;;
esac
