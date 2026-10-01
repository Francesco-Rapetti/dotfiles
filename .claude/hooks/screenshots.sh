#!/bin/bash

# PostToolUse hook of Claude Code, after Edit and Write: when the file is part of SketchyBar (a
# plugin, sketchybarrc, a helper or colors.sh) it reminds Claude of the screenshots of the README,
# as CLAUDE.md says. It only adds context: it never blocks the edit

file="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
case "$file" in
  */sketchybar/plugins/* | */sketchybar/sketchybarrc | */sketchybar/helpers/* | */sketchybar/colors.sh) ;;
  *) exit 0 ;;
esac

jq -n --arg file "sketchybar/${file##*/sketchybar/}" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "Hai modificato \($file): se cambia qualcosa di visibile nella barra o in un popup, prima di finire aggiorna gli screenshot del README con dati finti come dice CLAUDE.md (screenshots/take.sh <shot>)."
  }
}'
