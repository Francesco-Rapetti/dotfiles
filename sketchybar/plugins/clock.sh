#!/bin/sh

# Date and time, with the weekday in the language of the Mac. A click opens the popup with the
# calendar of the month, drawn by helpers/calendar_month each time it opens so that it is always the
# current day; a click on the calendar opens the Calendar app

MONTH_HELPER="$CONFIG_DIR/helpers/calendar_month"
MONTH_IMAGE="${TMPDIR:-/tmp}/sketchybar_calendar_month.png"

. "$CONFIG_DIR/colors.sh"

case "$SENDER" in
  mouse.clicked)
    # The helper prints the scale that shows the image at its size in points
    scale="$("$MONTH_HELPER" "$MONTH_IMAGE" $TEXT $SUBTEXT $PRIMARY $ON_PRIMARY)" &&
      sketchybar --set clock.month background.image.scale="$scale" background.image="$MONTH_IMAGE"
    sketchybar --set "$NAME" popup.drawing=toggle
    exit 0
    ;;
  mouse.exited.global)
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
    ;;
esac

# date takes the weekday from LC_TIME, which SketchyBar doesn't set. AppleLocale is the language
# and the region, e.g. it_IT, or en_IT for English with the formats of Italy: when macOS has no
# locale for the pair, one of the same language will do
LOCALE="$(defaults read -g AppleLocale 2>/dev/null)"
LOCALE="${LOCALE%%@*}"
[ -d "/usr/share/locale/$LOCALE.UTF-8" ] ||
  LOCALE="$(ls /usr/share/locale | sed -n "s/^\(${LOCALE%%_*}_[A-Z]*\)\.UTF-8$/\1/p" | head -1)"

sketchybar --set "$NAME" label="$(LC_TIME="$LOCALE.UTF-8" date '+%a %d/%m  %H:%M')"
