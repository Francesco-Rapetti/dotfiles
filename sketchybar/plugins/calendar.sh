#!/usr/bin/env bash

# Next event of the day from the macOS calendars, or today's all-day events once there are no more
# timed ones. helpers/calendar_events sends it with calendar_change (KIND and LABEL, already in the
# language of the Mac)
# The icon is an SF Symbol, so it needs the SF Pro font (brew install --cask font-sf-pro)

CALENDAR=􀉉  # calendar

TEXT=0xffcdd6f4
RED=0xfff38ba8

# Only calendar_change carries the event: the forced update at startup has nothing to show
[ "$SENDER" = "calendar_change" ] || exit 0

case "$KIND" in
  upcoming | ongoing | allday) item=(drawing=on icon.color=$TEXT label="$LABEL") ;;
  denied) item=(drawing=on icon.color=$RED label="$LABEL") ;;
  *) item=(drawing=off) ;;
esac

sketchybar --set "$NAME" icon="$CALENDAR" "${item[@]}"
