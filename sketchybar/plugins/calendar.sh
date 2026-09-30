#!/usr/bin/env bash

# Next event of the day from the macOS calendars, or today's all-day events once there are no more
# timed ones. helpers/calendar_events sends it with calendar_change (KIND, TIME and TITLE)
# The icon is an SF Symbol, so it needs the SF Pro font (brew install --cask font-sf-pro)

CALENDAR=􀉉  # calendar

TEXT=0xffcdd6f4
RED=0xfff38ba8

# Only calendar_change carries the event: the forced update at startup has nothing to show
[ "$SENDER" = "calendar_change" ] || exit 0

case "$KIND" in
  upcoming) item=(drawing=on icon.color=$TEXT label="$TIME  $TITLE") ;;
  ongoing) item=(drawing=on icon.color=$TEXT label="$TITLE · fino alle $TIME") ;;
  allday) item=(drawing=on icon.color=$TEXT label="$TITLE") ;;
  denied) item=(drawing=on icon.color=$RED label="Nessun accesso al calendario") ;;
  *) item=(drawing=off) ;;
esac

sketchybar --set "$NAME" icon="$CALENDAR" "${item[@]}"
