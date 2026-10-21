#!/usr/bin/env bash
# Open a path from a notification click.
#
# Stock Taildrop toasts use --exec xdg-open. xdg-open runs Terminal=true
# desktop files (nvim.desktop for text/plain) with `env nvim file` and no
# terminal, so nvim writes a swap file and no window appears. Markdown is
# also sniffed as text/plain, so it never reaches omawrite.desktop.
set -euo pipefail

target=${1:-}
if [[ -z $target ]]; then
  echo "usage: open-file.sh <path-or-url>" >&2
  exit 1
fi

if [[ $target == *://* && $target != file://* ]]; then
  exec xdg-open "$target"
fi

if [[ $target == file://* ]]; then
  target=${target#file://}
fi

if [[ ! -e $target ]]; then
  omarchy-notification-send "Can't open file" "$target" -u normal -g 󰅖 || true
  exit 1
fi

if [[ -d $target ]]; then
  exec xdg-open "$target"
fi

desktop_file_for() {
  local id=$1 d alt
  local paths=("${XDG_DATA_HOME:-$HOME/.local/share}")
  local rest="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  local IFS=:
  local extra
  read -ra extra <<<"$rest"
  paths+=("${extra[@]}")
  for d in "${paths[@]}"; do
    [[ -r $d/applications/$id ]] && { printf '%s\n' "$d/applications/$id"; return 0; }
    alt=${id/-//}
    [[ $alt != "$id" && -r $d/applications/$alt ]] && { printf '%s\n' "$d/applications/$alt"; return 0; }
  done
  return 1
}

launch_desktop() {
  local desk=$1 file=$2
  exec setsid uwsm-app -- gio launch "$desk" "$file"
}

# *.md is text/plain on this mime db, so xdg-open picks nvim.desktop.
# omawrite is the GUI markdown handler the user already set.
lower=${target,,}
case $lower in
*.md | *.markdown | *.mdown | *.mkd)
  oma=$(desktop_file_for omawrite.desktop || true)
  if [[ -n $oma ]]; then
    launch_desktop "$oma" "$target"
  fi
  ;;
esac

mime=$(xdg-mime query filetype "$target" 2>/dev/null || file --brief --mime-type -- "$target" || true)
desktop_id=$(xdg-mime query default "$mime" 2>/dev/null || true)
desk=
if [[ -n $desktop_id ]]; then
  desk=$(desktop_file_for "$desktop_id" || true)
fi

if [[ -n $desk ]] && grep -qiE '^[[:space:]]*Terminal[[:space:]]*=[[:space:]]*true' "$desk"; then
  exec_line=$(grep -E '^Exec=' "$desk" | head -1)
  exec_line=${exec_line#Exec=}
  # Field codes are the file; we pass $target ourselves.
  exec_line=${exec_line//%[fFuUdDnN]/}
  # shellcheck disable=SC2206
  parts=($exec_line)
  i=0
  if [[ ${parts[0]:-} == env ]]; then
    i=1
    while (( i < ${#parts[@]} )) && [[ ${parts[i]} == *=* ]]; do
      ((i++)) || true
    done
  fi
  bin=${parts[i]:-nvim}
  exec omarchy-launch-tui "$bin" "$target"
fi

exec xdg-open "$target"
