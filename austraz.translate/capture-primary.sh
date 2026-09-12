#!/usr/bin/env bash
# Snapshot the primary selection so a later right-click can still see it
# after the app has cleared the highlight.
set -uo pipefail
dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-llm"
mkdir -p "$dir"
text=$(cat)
[[ -n $text ]] || exit 0
if ((${#text} > 16000)); then
  text=${text:0:16000}
fi
printf '%s' "$text" >"$dir/primary.txt"
date +%s >"$dir/primary.ts"
