#!/usr/bin/env bash
# Translate selected text FR↔EN via Lemonade on the NPU.
# Super+Shift+T translates immediately.
# Shares the image-autoname lock so we queue, never evict a foreign model.
set -uo pipefail

LLM_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$LLM_DIR/lib.sh"

WORKDIR="${XDG_RUNTIME_DIR:-/tmp}/omarchy-llm"
mkdir -p "$WORKDIR"
PRIMARY_TXT="$WORKDIR/primary.txt"
PRIMARY_TS="$WORKDIR/primary.ts"
PENDING="$WORKDIR/translate-pending.txt"
MAX_CHARS=12000
FRESH_SECS=90

MODE=run
STDOUT=0
FILE=""
QUIET=0

while (( $# )); do
  case "$1" in
    --menu) MODE=menu; shift ;;
    --stdout) STDOUT=1; QUIET=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --file)
      FILE=${2:-}
      shift 2
      ;;
    --) shift; break ;;
    -h | --help)
      printf '%s\n' "Usage: omarchy-llm-translate [--menu] [--stdout] [--file PATH]"
      exit 0
      ;;
    *) break ;;
  esac
done

read_live_primary() {
  timeout 0.2 wl-paste --primary --type text --no-newline 2>/dev/null || true
}

read_snapshot_primary() {
  local now last=0
  [[ -f $PRIMARY_TXT && -f $PRIMARY_TS ]] || return 0
  last=$(tr -d '\n' <"$PRIMARY_TS" 2>/dev/null || echo 0)
  [[ $last =~ ^[0-9]+$ ]] || return 0
  now=$(date +%s)
  ((now - last <= FRESH_SECS)) || return 0
  cat "$PRIMARY_TXT" 2>/dev/null || true
}

read_clipboard() {
  timeout 0.2 wl-paste --type text --no-newline 2>/dev/null || true
}

# Electron/Chrome (Cursor, Brave, …) never put a highlight on the Wayland
# primary selection. Super+C already injects Ctrl+C; we do the same here.
active_window_is_terminal() {
  hyprctl -j activewindow 2>/dev/null \
    | jq -e '.tags[]? | sub("\\*$";"") == "terminal"' >/dev/null 2>&1
}

send_copy() {
  local mods=CTRL key=C
  local mods_json key_json
  if active_window_is_terminal; then
    key=Insert
  fi
  mods_json=$(jq -n --arg v "$mods" '$v')
  key_json=$(jq -n --arg v "$key" '$v')
  # Same injection Super+C uses (clipboard.lua). Swallowing errors hid a
  # failed dispatch; log it so a dead copy is visible.
  if ! hyprctl dispatch "hl.dsp.send_key_state({ mods = $mods_json, key = $key_json, state = \"down\", window = \"activewindow\" })" >/dev/null; then
    llm_log "translate copy: send down failed mods=$mods key=$key"
    hyprctl dispatch sendshortcut "$mods,$key," >/dev/null 2>&1 || true
  fi
  sleep 0.05
  hyprctl dispatch "hl.dsp.send_key_state({ mods = $mods_json, key = $key_json, state = \"up\", window = \"activewindow\" })" >/dev/null || true
}

grab_from_focused_app() {
  local before after i
  before=$(read_clipboard)
  send_copy
  for i in $(seq 1 8); do
    sleep 0.05
    after=$(read_clipboard)
    if [[ -n $after && $after != "$before" ]]; then
      printf '%s' "$after"
      return 0
    fi
  done
  return 1
}

trim_text() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

load_source_text() {
  local text=""
  if [[ -n $FILE ]]; then
    [[ -f $FILE ]] || return 1
    text=$(cat -- "$FILE")
  elif ((STDOUT)) && [[ ! -t 0 ]]; then
    # Overlay pipes the source on stdin. Hyprland binds attach /dev/null —
    # that is not a source, so we must not `cat` it.
    text=$(cat)
  else
    text=$(read_live_primary)
    [[ -n $text ]] || text=$(read_snapshot_primary)
    [[ -n $text ]] || text=$(grab_from_focused_app)
  fi
  text=$(trim_text "$text")
  [[ -n $text ]] || return 1
  printf '%s' "$text"
}

cursor_payload() {
  local cursor monitors hit
  cursor=$(hyprctl -j cursorpos 2>/dev/null) || cursor='{"x":0,"y":0}'
  monitors=$(hyprctl -j monitors 2>/dev/null) || monitors='[]'
  hit=$(jq -nc --argjson c "$cursor" --argjson m "$monitors" '
    ($m | map(select(
      (.x // 0) <= $c.x
      and $c.x < ((.x // 0) + (.width // 0))
      and (.y // 0) <= $c.y
      and $c.y < ((.y // 0) + (.height // 0))
    )) | .[0]) as $mon
    | {
        x: ($c.x - ($mon.x // 0)),
        y: ($c.y - ($mon.y // 0)),
        screen: ($mon.name // "")
      }
  ')
  printf '%s' "$hit"
}

if [[ $MODE == menu ]]; then
  text=$(load_source_text) || exit 0
  (( ${#text} >= 2 )) || exit 0
  if (( ${#text} > MAX_CHARS )); then
    llm_notify -u normal "Translation" "Sélection trop longue"
    exit 0
  fi
  printf '%s' "$text" >"$PENDING"
  pos=$(cursor_payload)
  payload=$(jq -nc --arg f "$PENDING" --argjson p "$pos" '{file:$f} + $p')
  omarchy-shell shell summon austraz.translate "$payload" >/dev/null 2>&1 || exit 0
  exit 0
fi

text=$(load_source_text) || {
  llm_log "translate skip: no selection"
  ((QUIET)) || llm_notify -u normal "Translation" "Aucune sélection"
  exit 3
}

if (( ${#text} > MAX_CHARS )); then
  ((QUIET)) || llm_notify -u normal "Translation" "Sélection trop longue"
  exit 4
fi

chars=${#text}
kind=small
timeout_sec=30
# One shot: do not let llm_chat retry and stretch past 30s.
LLM_CHAT_RETRY=0
export LLM_CHAT_RETRY
max_tokens=$((chars + 128))
((max_tokens < 128)) && max_tokens=128
((max_tokens > 768)) && max_tokens=768

detect_lang() {
  python3 -c '
import re, sys
s = sys.stdin.read().lower()
fr = len(re.findall(r"[àâäéèêëïîôùûüçœ]", s))
fr += len(re.findall(r"\b(le|la|les|un|une|des|et|est|que|dans|pour|avec|pas|sur|ce|qui|du|au|je|tu|nous|vous|ils|elle|mais|donc|aussi|selon)\b", s))
en = len(re.findall(r"\b(the|and|or|to|of|in|is|for|with|that|this|are|not|be|on|as|at|by|from|it|an|according|report|downloaded|without)\b", s))
print("fr" if fr > en else "en")
'
}

same_lang() {
  local src=$1 out
  out=$(printf '%s' "$2" | detect_lang)
  [[ $out == "$src" ]]
}

src_lang=$(printf '%s' "$text" | detect_lang)
if [[ $src_lang == fr ]]; then
  dst_lang=en
  wrap=$'Translate the following French into English.\nReply with the English translation only. Do not repeat the French.\n\n<<<\n'"$text"$'\n>>>'
else
  dst_lang=fr
  wrap=$'Traduis le texte anglais suivant en français.\nRéponds uniquement par la traduction française. Ne recopie pas l'\''anglais.\n\n<<<\n'"$text"$'\n>>>'
fi

NOTIFY_ID=0

TRANSLATE_APP=(--app-name austraz.translate)

notify_progress() {
  ((QUIET)) && return 0
  local id
  id=$(omarchy-notification-send -p "${TRANSLATE_APP[@]}" -u critical "Translation" "FR ↔ EN via le NPU…" 2>/dev/null || true)
  [[ $id =~ ^[0-9]+$ ]] && NOTIFY_ID=$id
}

# Replace the in-progress toast in place (critical toasts do not auto-expire).
notify_done() {
  local title=$1 body=$2 timeout=${3:-8000} urgency=${4:-normal}
  ((QUIET)) && return 0
  local -a args=("${TRANSLATE_APP[@]}" -u "$urgency")
  [[ $urgency == critical ]] || args+=(-t "$timeout")
  args+=("$title" "$body")
  if [[ $NOTIFY_ID =~ ^[0-9]+$ ]] && ((NOTIFY_ID > 0)); then
    omarchy-notification-send -r "$NOTIFY_ID" "${args[@]}" >/dev/null 2>&1 \
      || llm_notify "${args[@]}"
  else
    llm_notify "${args[@]}"
  fi
}

# Toast width ~380px minus icon/padding ≈ 42 columns at the notification font.
visual_lines() {
  python3 -c '
import sys
width = 42
text = sys.stdin.read()
if not text.strip():
    print(1)
    raise SystemExit
n = 0
for raw in text.splitlines() or [""]:
    s = raw.replace("\t", "    ")
    if not s:
        n += 1
        continue
    n += max(1, (len(s) + width - 1) // width)
print(max(1, n))
'
}

notify_result() {
  local body=$1 lines ms
  lines=$(printf '%s' "$body" | visual_lines)
  if ((lines > 3)); then
    notify_done "Translation copied" "$body" 0 critical
  else
    ms=$((lines * 3000))
    ((ms < 3000)) && ms=3000
    notify_done "Translation copied" "$body" "$ms" normal
  fi
}

((QUIET)) || notify_progress

LLM_SYSTEM='Tu es un traducteur FR↔EN. Tu ne fais que traduire. Pas de préambule, pas de guillemets, pas de reformulation dans la langue source.'
export LLM_SYSTEM

extract_translation() {
  python3 -c '
import re, sys
t = sys.stdin.read()
t = re.sub(r"<think>.*?</think>", "", t, flags=re.S | re.I)
t = t.strip()
if not t:
    raise SystemExit(1)
lines = [ln.strip() for ln in t.splitlines() if ln.strip()]
first = lines[0].lower()
cot = first.startswith((
    "okay", "ok,", "ok ", "the user", "i need", "let me", "first,",
    "looking at", "the text", "the input", "alright", "<think>",
))
if cot:
    skip = ("so the", "therefore", "in conclusion", "the translation", "final answer")
    for ln in reversed(lines):
        low = ln.lower()
        if "<think>" in low or "</think>" in low:
            continue
        if low.startswith(skip):
            ln = re.sub(r"^(the translation is|final answer):?\s*", "", ln, flags=re.I).strip()
        if ln and len(ln) < 800:
            print(ln)
            break
    else:
        print(lines[-1])
else:
    sys.stdout.write(t)
'
}

translated=$(printf '%s' "$wrap" | timeout --signal=TERM --kill-after=2 30 \
  bash -c 'source "$1"; llm_chat "$2" "$3" "$4" "$5"' \
  bash "$LLM_DIR/lib.sh" "$kind" "$timeout_sec" "$max_tokens" 8) || {
  status=$?
  if [[ $status -eq 2 ]]; then
    notify_done "Translation" "NPU occupé — réessaie dans un moment" 8000
    release_idle_runtimes
    exit 2
  fi
  notify_done "Translation" "Traduction impossible" 8000
  release_idle_runtimes
  exit 1
}

translated=$(printf '%s' "$translated" | tr -d '\r' | extract_translation) || translated=""
translated=$(printf '%s' "$translated" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [[ -n $translated ]] && same_lang "$src_lang" "$translated"; then
  llm_log "translate same-lang retry src=$src_lang"
  if [[ $src_lang == en ]]; then
    wrap=$'ENGLISH → FRENCH. Output French only.\n\n'"$text"
  else
    wrap=$'FRENCH → ENGLISH. Output English only.\n\n'"$text"
  fi
  retry=$(printf '%s' "$wrap" | timeout --signal=TERM --kill-after=2 15 \
    bash -c 'source "$1"; llm_chat "$2" "$3" "$4" "$5"' \
    bash "$LLM_DIR/lib.sh" "$kind" 15 "$max_tokens" 8) || retry=""
  retry=$(printf '%s' "$retry" | tr -d '\r' | extract_translation) || retry=""
  retry=$(printf '%s' "$retry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [[ -n $retry ]] && ! same_lang "$src_lang" "$retry"; then
    translated=$retry
  fi
fi
[[ -n "$translated" ]] || {
  notify_done "Translation" "Réponse vide" 8000
  release_idle_runtimes
  exit 1
}

printf '%s' "$translated" | wl-copy

if ((STDOUT)); then
  printf '%s' "$translated"
else
  notify_result "$translated"
fi

release_idle_runtimes
exit 0
