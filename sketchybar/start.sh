#!/usr/bin/env bash

# Starts SketchyBar, and starts it again whenever it exits: after a crash, or when notification.sh
# stops it to run a new version. AeroSpace runs this at login in place of sketchybar
# (after-startup-command in aerospace.toml), with the environment the plugins expect. Not launchd:
# a launchd job would give them another PATH, and when SketchyBar exits it would kill them all,
# since they are in its process group, e.g. the upgrade that is restarting it.
# After a crash it writes to LOG what the crash report of macOS says, the newest crash first, and
# adds the crash to CRASHES, which notification.sh counts in its green badge, with a popup row
# that opens LOG. To stop SketchyBar for good, stop this first: pkill -f sketchybar/start.sh

LOG="$HOME/Library/Logs/sketchybar-crash.log"
CRASHES="${TMPDIR:-/tmp}/sketchybar_crashes"  # for notification.sh: the time of each crash, one per line
LOCK="${TMPDIR:-/tmp}/sketchybar_start.lock"
REPORTS="$HOME/Library/Logs/DiagnosticReports"
REPORT_WAIT=60  # seconds that macOS may take to write the crash report
SHORT_RUN=10    # a SketchyBar that exits sooner, e.g. at every start, waits as long to start again

# Only one at a time, since AeroSpace runs this again whenever it restarts. The lock holds the pid
# of the one running, and survives a reboot: then the pid may be another process's
if ! shlock -f "$LOCK" -p $$; then
  ps -o command= -p "$(cat "$LOCK")" | grep -q 'sketchybar/start\.sh' && exit 0
  echo $$ > "$LOCK"
fi

# crashed <exit status>: whether SketchyBar crashed, killed by SIGILL, SIGTRAP, SIGABRT, SIGEMT,
# SIGFPE, SIGBUS, SIGSEGV or SIGSYS (128 + the signal). SIGTERM, SIGINT, SIGHUP and SIGKILL mean
# that something stopped it
crashed() {
  case $1 in
    132 | 133 | 134 | 135 | 136 | 138 | 139 | 140) return 0 ;;
    *) return 1 ;;
  esac
}

# report <pid>: the crash report of the SketchyBar with that pid, which macOS writes a few seconds
# after the crash, e.g. ~/Library/Logs/DiagnosticReports/sketchybar-2026-10-02-155815.ips: a line
# of JSON with the header, then the JSON of the report. Until then jq can't read it
report() {
  local i file
  for ((i = 0; i < REPORT_WAIT; i++)); do
    for file in $(find "$REPORTS" -maxdepth 1 -name 'sketchybar*.ips' -mmin -5 2>/dev/null); do
      [ "$(jq -s '.[1].pid' "$file" 2>/dev/null)" = "$1" ] && echo "$file" && return
    done
    sleep 1
  done
  return 1
}

# summary <report>: what the crash report says: the exception, the message of the library that
# stopped it, the version of macOS, and the stack of the thread that crashed, with the offset in
# the binary where a frame has no symbol
summary() {
  jq -rs '
    def hex: [recurse(if . >= 16 then (. / 16 | floor) else empty end) | . % 16] | reverse
             | map("0123456789abcdef"[.:. + 1]) | "0x" + join("");
    .[0] as $header | .[1] as $report | $report.threads[$report.faultingThread] as $thread
    | "Eccezione: \($report.exception.type) (\($report.exception.signal)), \($report.termination.indicator)",
      ([$report.asi // {} | .[][]] | select(length > 0) | "Messaggio: " + join("; ")),
      "Sistema: \($header.os_version)",
      "",
      "Thread \($report.faultingThread)\($thread.queue // "" | if . == "" then "" else " (\(.))" end), quello del crash:",
      ($thread.frames | to_entries[] | .key as $index | .value
       | "\($index)\t\($report.usedImages[.imageIndex].name // "?")\t\(.symbol // (.imageOffset | hex))"
         + (if .symbolLocation then " + \(.symbolLocation)" else "" end))
  ' "$1" | awk -F'\t' 'NF == 3 { printf "  %-3s %-28s %s\n", $1, $2, $3; next } { print }'
}

# record <pid> <exit status> <time>: the crash at the top of LOG, then in CRASHES
record() {
  local report entry
  report="$(report "$1")"
  entry="$(
    echo "=== $(date -r "$3" '+%d/%m/%Y %H:%M:%S') ==="
    echo "SketchyBar è andato in crash (SIG$(kill -l $(($2 - 128)))) ed è ripartito."
    echo "Versione: $(sketchybar --version)"
    if [ -n "$report" ]; then
      summary "$report"
      echo
      echo "Il report completo, che si apre con Console: ${report/#$HOME/~}"
    else
      echo "macOS non ha scritto il report del crash."
    fi
  )"
  { printf '%s\n\n' "$entry"; cat "$LOG" 2>/dev/null; } > "$LOG.$$"
  mv "$LOG.$$" "$LOG"
  echo "$3" >> "$CRASHES"
}

while :; do
  started=$(date +%s)
  sketchybar &
  pid=$!
  wait $pid
  status=$?
  crashed $status && record $pid $status "$(date +%s)" &
  [ $(($(date +%s) - started)) -lt $SHORT_RUN ] && sleep $SHORT_RUN
done
