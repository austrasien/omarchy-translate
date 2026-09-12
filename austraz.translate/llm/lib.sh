#!/usr/bin/env bash
# Shared Lemonade/Ollama client. One NPU slot, never evict a model we did not load.
# Shares state + lock with image-autoname so screenshot naming and these tools serialize.

LLM_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/llm.conf"
[[ -f $CONF ]] && source "$CONF"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/image-autoname"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/image-autoname.lock"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-llm"
LLM_HOLDING_LOCK=${LLM_HOLDING_LOCK:-0}

mkdir -p "$STATE_DIR" "$LOG_DIR"

llm_log() {
  printf '%s %s\n' "$(date +'%F %T')" "$*" >>"$LOG_DIR/llm.log"
}

llm_notify() {
  command -v omarchy-notification-send >/dev/null || return 0
  omarchy-notification-send "$@" >/dev/null 2>&1 || true
}

abort_ollama_runner() {
  [[ -f $STATE_DIR/started-ollama ]] || return 0
  local pid
  pid=$(pgrep -x ollama | head -n1) || return 0
  pkill -P "$pid" -f '/usr/lib/ollama/llama-server' 2>/dev/null || true
}

lemonade_gui_running() {
  pgrep -x lemonade-app >/dev/null 2>&1
}

lemonade_api_base() {
  local given=${1:-} host p
  local -a hosts=()
  [[ -n $given ]] && hosts+=("${given%/}")
  hosts+=(http://127.0.0.1:13305 http://127.0.0.1:8000)
  local seen=""
  for host in "${hosts[@]}"; do
    host=${host%/}
    [[ $seen == *" $host "* ]] && continue
    seen+=" $host "
    for p in api/v1 v1; do
      if curl -sf --max-time 1 "$host/$p/models" >/dev/null; then
        printf '%s' "$host/$p"
        return 0
      fi
    done
  done
  return 1
}

lemonade_loaded_model() {
  local base=${1:-} json
  [[ -n $base ]] || base=$(lemonade_api_base "${LEMONADE_HOST:-}") || return 0
  json=$(curl -sf --max-time 2 "$base/health") || return 0
  jq -r '.model_loaded // empty' <<<"$json" | awk 'NF && $0 != "null" { print; exit }'
}

# want=our id, have=currently loaded id.
# use = already loaded (do not unload)
# load = slot free, we may load and later unload
# skip = another model occupies the NPU; do not evict
lemonade_slot_action() {
  local want=${1:-} have=${2:-}
  if [[ -z $have || $have == null ]]; then
    printf '%s' load
    return
  fi
  if [[ $have == "$want" || $have == "$want"* || $want == "$have"* ]]; then
    printf '%s' use
    return
  fi
  printf '%s' skip
}

llm_id_is_vision() {
  local id=${1:-}
  [[ $id =~ [Vv][Ll] || $id =~ [Ll]lava || $id =~ [Mm]ini[Cc][Pp][Mm] ]]
}

llm_id_is_thinking() {
  local id=${1:-}
  [[ $id =~ [Dd]eep[Ss]eek || $id =~ [Rr]1 || $id =~ -tk- || $id =~ [Tt]hink ]]
}

# FastFlowLM 1.0.4 aborts on qwen3-it:4b (empty logits .back()).
llm_id_is_crashing() {
  local id=${1:-}
  [[ $id == *qwen3-it* ]]
}

llm_we_loaded() {
  local have=${1:-} ours
  [[ -n $have && -f $STATE_DIR/our-lemonade-model ]] || return 1
  ours=$(tr -d '\n' <"$STATE_DIR/our-lemonade-model")
  [[ -n $ours && ( $have == "$ours" || $have == "$ours"* || $ours == "$have"* ) ]]
}

note_vision_use() {
  mkdir -p "$STATE_DIR"
  date +%s >"$STATE_DIR/last-vision-use"
}

remember_our_lemonade_model() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" >"$STATE_DIR/our-lemonade-model"
  note_vision_use
}

lemonade_unload_model() {
  local base model=$1
  [[ -n $model ]] || return 0
  base=$(lemonade_api_base "${LEMONADE_HOST:-}") || return 0
  curl -sf --max-time 15 "$base/unload" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg m "$model" '{model_name:$m}')" >/dev/null || true
}

ensure_lemonade_server() {
  local host=${LEMONADE_HOST:-http://127.0.0.1:13305} i
  lemonade_api_base "$host" >/dev/null && return 0
  [[ ${LLM_START_SERVERS:-1} == 1 ]] || return 1
  command -v lemond >/dev/null || return 1
  mkdir -p "$STATE_DIR"
  if systemctl --user is-active --quiet lemond.service 2>/dev/null; then
    :
  elif systemctl --user start lemond.service 2>/dev/null; then
    printf '%s\n' "$(date +%s)" >"$STATE_DIR/started-lemond"
  else
    return 1
  fi
  for i in $(seq 1 30); do
    lemonade_api_base "$host" >/dev/null && return 0
    sleep 0.5
  done
  return 1
}

ensure_ollama_server() {
  local host=${OLLAMA_HOST:-http://127.0.0.1:11434} logdir i
  curl -sf --max-time 1 "$host/api/version" >/dev/null && return 0
  [[ ${LLM_START_SERVERS:-1} == 1 ]] || return 1
  command -v ollama >/dev/null || return 1
  mkdir -p "$STATE_DIR"
  if systemctl --user is-active --quiet ollama.service 2>/dev/null; then
    :
  elif systemctl --user start ollama.service 2>/dev/null; then
    printf '%s\n' "$(date +%s)" >"$STATE_DIR/started-ollama"
  else
    logdir="${XDG_STATE_HOME:-$HOME/.local/state}/image-autoname"
    mkdir -p "$logdir"
    nice -n 10 ollama serve >>"$logdir/ollama.log" 2>&1 &
    printf '%s\n' $! >"$STATE_DIR/started-ollama"
  fi
  for i in $(seq 1 20); do
    curl -sf --max-time 1 "$host/api/version" >/dev/null && return 0
    sleep 0.5
  done
  return 1
}

release_idle_runtimes() {
  local idle=${VISION_KEEP_ALIVE:-300} now last=0 ts=0 ours loaded
  now=$(date +%s)
  # Keep-alive is the most recent of last use AND when we started lemond.
  # Using only last-vision-use let image-autoname-watch stop a server we had
  # just launched for a text job (translate), mid-load.
  for tsfile in "$STATE_DIR/last-vision-use" "$STATE_DIR/started-lemond"; do
    [[ -f $tsfile ]] || continue
    ts=$(tr -d '\n' <"$tsfile" 2>/dev/null || echo 0)
    [[ $ts =~ ^[0-9]+$ ]] || continue
    ((ts > last)) && last=$ts
  done
  ((now - last >= idle)) || return 0

  if [[ -f $STATE_DIR/our-lemonade-model ]]; then
    ours=$(tr -d '\n' <"$STATE_DIR/our-lemonade-model")
    if lemonade_gui_running; then
      :
    elif [[ -n $ours ]]; then
      loaded=$(lemonade_loaded_model) || loaded=
      if [[ $loaded == "$ours" || $loaded == "$ours"* ]]; then
        lemonade_unload_model "$ours"
      fi
      rm -f "$STATE_DIR/our-lemonade-model"
    fi
  fi

  if [[ -f $STATE_DIR/started-lemond && ! lemonade_gui_running ]]; then
    [[ -f $STATE_DIR/our-lemonade-model ]] || {
      systemctl --user stop lemond.service 2>/dev/null || true
      rm -f "$STATE_DIR/started-lemond"
    }
  fi
}

lemonade_models_json() {
  local base=$1 json
  json=$(curl -sf --max-time 2 "$base/models?show_all=true") \
    || json=$(curl -sf --max-time 2 "$base/models") \
    || return 1
  printf '%s' "$json"
}

lemonade_pick_vision_model() {
  local preferred=${1:-} json
  json=$(cat)
  [[ -n $json ]] || return 1
  jq -r --arg m "$preferred" '
    def available: .downloaded != false;
    def is_vision:
      ((.labels // []) | index("image") | not)
      and (
        ((.labels // []) | index("vision"))
        or ((.id // "") | test("(?i)(qwen3vl|qwen2\\.?5vl|qwen2vl|-vl-|vl-it|minicpm-v|llava)"))
      );
    def npu_rank:
      if .recipe == "flm" then 0
      elif ((.id // "") | test("(?i)-FLM")) then 1
      elif .recipe == "ryzenai-llm" then 2
      else 3 end;
    [.data[]? | select(available and is_vision)] as $c
    | (
        if ($m | length) > 0 then
          $c | map(select(.id == $m or (.id | startswith($m)))) | .[0]
        else null end
      ) as $hit
    | if $hit then $hit.id
      else ($c | sort_by((.size // 1e9), npu_rank) | .[0].id // empty)
      end
  ' <<<"$json"
}

lemonade_pick_text_model() {
  local preferred=${1:-} prefer=${2:-small} json
  json=$(cat)
  [[ -n $json ]] || return 1
  jq -r --arg m "$preferred" --arg prefer "$prefer" '
    def available: .downloaded != false;
    def canon:
      ascii_downcase
      | gsub("-npu[0-9]+$";"")
      | gsub("-(flm|gguf)$";"")
      | gsub("[^a-z0-9]";"");
    def is_vl:
      ((.id // "") | test("(?i)(qwen3vl|qwen2\\.?5vl|qwen2vl|-vl-|vl-it|minicpm-v|llava)"));
    def is_vision:
      is_vl
      or (
        ((.labels // []) | index("vision"))
        and (((.labels // []) | index("chat")) | not)
      );
    def is_blocked:
      ((.id // "") | test("(?i)qwen3-it"));
    def is_text: available and (is_vision | not) and (is_blocked | not);
    def is_thinking:
      ((.labels // []) | index("reasoning"))
      or ((.id // "") | test("(?i)(deepseek|[-_.]r1[-_.]|r1-0528|-tk-|thinking)"));
    def npu_rank:
      if .recipe == "flm" then 0
      elif ((.id // "") | test("(?i)-FLM")) then 1
      else 2 end;
    def smallness:
      if ((.id // "") | test("(?i)(1b|1\\.5b|3b|4b)")) then 0
      elif ((.id // "") | test("(?i)(7b|8b)")) then 1
      else 2 end;
    [.data[]? | select(is_text)] as $all
    | (
        if ($m | length) > 0 then
          $all | map(select(
            .id == $m
            or (.id | startswith($m))
            or ((.id | canon) == ($m | canon))
          )) | .[0]
        else null end
      ) as $hit
    | if $hit then $hit.id
      elif $prefer == "small" then
        ($all | map(select(is_thinking | not))
          | sort_by(smallness, (.size // 1e9), npu_rank)
          | .[0].id // empty)

      else
        ($all | sort_by(-(.size // 0), npu_rank) | .[0].id // empty)
      end
  ' <<<"$json"
}

# Acquire the shared LLM lock. timeout 0 = non-blocking (return 2 if busy).
llm_acquire_lock() {
  local timeout=${1:-0}
  ((LLM_HOLDING_LOCK)) && return 0
  mkdir -p "$(dirname "$LOCK")"
  exec 8>"$LOCK"
  if [[ $timeout == 0 ]]; then
    flock -n 8 || return 2
  else
    flock -w "$timeout" 8 || return 2
  fi
  LLM_HOLDING_LOCK=1
}

lemonade_wait_ready() {
  local base=$1 want=$2 i health loaded bh
  for i in $(seq 1 60); do
    health=$(curl -sf --max-time 2 "$base/health" 2>/dev/null || true)
    loaded=$(jq -r '.model_loaded // empty' <<<"$health" 2>/dev/null || true)
    bh=$(jq -r --arg m "$want" '
      [.all_models_loaded[]? | select(.model_name == $m or (.model_name | startswith($m)))]
      | .[0].backend_health // empty
    ' <<<"$health" 2>/dev/null || true)
    if [[ ( $loaded == "$want" || $loaded == "$want"* ) && $bh == ready ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

llm_load_if_needed() {
  local base=$1 model=$2 action=$3
  case "$action" in
    skip) return 2 ;;
    use) note_vision_use; return 0 ;;
    load)
      remember_our_lemonade_model "$model"
      curl -sf --max-time 90 "$base/load" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg m "$model" '{model_name:$m}')" >/dev/null || true
      lemonade_wait_ready "$base" "$model" || return 1
      sleep 1
      ;;
  esac
}

# Text completion. Prints response. Exit 2 = skip (slot busy / lock).
# Usage: llm_chat <small|full> <timeout-sec> <max-tokens> [lock-wait-sec]
# Prompt on stdin (or $LLM_SYSTEM + stdin as user).
llm_chat() {
  local kind=$1 timeout=${2:-20} max_tokens=${3:-256} lock_wait=${4:-0}
  local system=${LLM_SYSTEM:-} user prompt
  user=$(cat)
  [[ -n $user ]] || return 1

  llm_acquire_lock "$lock_wait" || { llm_log "chat skip: lock"; return 2; }

  local base json model have action resp jsonf content
  if ! ensure_lemonade_server; then
    llm_log "chat: lemonade down"
    return 1
  fi
  base=$(lemonade_api_base "$LEMONADE_HOST") || return 1
  json=$(lemonade_models_json "$base") || return 1

  have=$(lemonade_loaded_model "$base")

  if [[ $kind == full ]]; then
    model=$(printf '%s' "$json" | lemonade_pick_text_model "$LLM_TEXT_FULL" full) || return 1
  else
    model=$(printf '%s' "$json" | lemonade_pick_text_model "$LLM_TEXT_SMALL" small) || true
    if [[ -z $model || $model == null ]] || llm_id_is_crashing "$model" || llm_id_is_thinking "$model"; then
      model=$(printf '%s' "$json" | lemonade_pick_vision_model "$LLM_VISION") || return 1
      llm_log "chat small: no safe text model, using vision $model"
    fi
  fi
  [[ -n $model && $model != null ]] || return 1
  if llm_id_is_crashing "$model"; then
    llm_log "chat skip: $model crashes FLM"
    return 1
  fi
  if [[ $kind == small ]] && llm_id_is_thinking "$model"; then
    llm_log "chat skip: refusing thinking model $model for small"
    return 1
  fi
  action=$(lemonade_slot_action "$model" "$have")
  if [[ $action == skip ]]; then
    local health busy pinned
    health=$(curl -sf --max-time 2 "$base/health" 2>/dev/null || true)
    busy=$(jq -r '[.all_models_loaded[]? | select(.is_busy == true or .is_streaming == true)] | length' <<<"$health" 2>/dev/null || echo 0)
    pinned=$(jq -r '[.all_models_loaded[]? | select(.pinned == true)] | length' <<<"$health" 2>/dev/null || echo 0)
    if [[ ${busy:-0} != 0 ]]; then
      llm_log "chat skip: $have busy"
      return 2
    fi
    if llm_we_loaded "$have" || [[ ${LLM_STEAL_SLOT:-0} == 1 && ${pinned:-0} == 0 ]]; then
      llm_log "chat switch: $have -> $model"
      # Let Lemonade replace the slot; a hard unload races FLM and crashes it.
      action=load
    else
      llm_log "chat skip: $have occupies NPU"
      return 2
    fi
  fi

  llm_load_if_needed "$base" "$model" "$action" || return 2
  llm_log "chat $kind model=$model action=$action"
  note_vision_use

  prompt=$user
  jsonf=$(mktemp)
  if [[ -n $system ]]; then
    jq -n \
      --arg model "$model" \
      --arg system "$system" \
      --arg user "$prompt" \
      --argjson max "$max_tokens" \
      '{
        model: $model,
        temperature: 0.2,
        max_tokens: $max,
        enable_thinking: false,
        thinking: false,
        messages: [
          {role: "system", content: $system},
          {role: "user", content: $user}
        ]
      }' >"$jsonf"
  else
    jq -n \
      --arg model "$model" \
      --arg user "$prompt" \
      --argjson max "$max_tokens" \
      '{
        model: $model,
        temperature: 0.2,
        max_tokens: $max,
        enable_thinking: false,
        thinking: false,
        messages: [{role: "user", content: $user}]
      }' >"$jsonf"
  fi

  resp=$(curl -sf --max-time "$timeout" "$base/chat/completions" \
    -H 'Content-Type: application/json' \
    --data-binary @"$jsonf") || {
    if [[ ${LLM_CHAT_RETRY:-1} != 1 ]]; then
      llm_log "chat curl failed timeout=$timeout model=$model"
      rm -f "$jsonf"
      return 1
    fi
    llm_log "chat curl failed timeout=$timeout model=$model — retry once"
    lemonade_wait_ready "$base" "$model" || {
      llm_log "chat retry: model not ready"
      rm -f "$jsonf"
      return 1
    }
    resp=$(curl -sf --max-time "$timeout" "$base/chat/completions" \
      -H 'Content-Type: application/json' \
      --data-binary @"$jsonf") || {
      llm_log "chat curl failed timeout=$timeout model=$model"
      rm -f "$jsonf"
      return 1
    }
  }
  rm -f "$jsonf"
  note_vision_use
  content=$(jq -r '.choices[0].message.content // empty' <<<"$resp")
  if [[ -z $content || $content == null ]]; then
    content=$(jq -r '.choices[0].message.reasoning_content // empty' <<<"$resp")
  fi
  printf '%s' "$content" | llm_strip_think | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Vision. $1 = image path. Prompt on stdin. Prints response. Exit 2 = skip.
llm_see() {
  local file=$1 timeout=${2:-45} max_tokens=${3:-128} lock_wait=${4:-20}
  local prompt mime tmp imgf jsonf resp json model have action base
  [[ -f $file ]] || return 1
  prompt=$(cat)
  [[ -n $prompt ]] || return 1

  llm_acquire_lock "$lock_wait" || { llm_log "see skip: lock"; return 2; }

  if ! ensure_lemonade_server; then
    llm_log "see: lemonade down, trying ollama"
    llm_see_ollama "$file" "$prompt" "$timeout" && return 0
    return 1
  fi
  base=$(lemonade_api_base "$LEMONADE_HOST") || return 1
  json=$(lemonade_models_json "$base") || return 1
  model=$(printf '%s' "$json" | lemonade_pick_vision_model "$LLM_VISION") || return 1
  [[ -n $model && $model != null ]] || return 1
  have=$(lemonade_loaded_model "$base")
  action=$(lemonade_slot_action "$model" "$have")
  case "$action" in
    skip)
      llm_log "see skip: $have occupies NPU"
      return 2
      ;;
  esac
  llm_load_if_needed "$base" "$model" "$action" || return 2
  llm_log "see model=$model action=$action"

  tmp=$(mktemp --suffix=.jpg)
  magick "$file" -auto-orient -resize '1024x1024>' -strip -quality 75 "$tmp" 2>/dev/null || cp -- "$file" "$tmp"
  mime=$(file --brief --mime-type "$tmp")
  imgf=$(mktemp)
  jsonf=$(mktemp)
  base64 -w0 "$tmp" >"$imgf"
  rm -f "$tmp"
  jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --arg mime "$mime" \
    --rawfile img "$imgf" \
    --argjson max "$max_tokens" \
    '{
      model: $model,
      temperature: 0.1,
      max_tokens: $max,
      messages: [{
        role: "user",
        content: [
          {type: "text", text: $prompt},
          {type: "image_url", image_url: {url: ("data:" + $mime + ";base64," + $img)}}
        ]
      }]
    }' >"$jsonf"
  rm -f "$imgf"
  resp=$(curl -sf --max-time "$timeout" "$base/chat/completions" \
    -H 'Content-Type: application/json' \
    --data-binary @"$jsonf") || { rm -f "$jsonf"; return 1; }
  rm -f "$jsonf"
  note_vision_use
  jq -r '.choices[0].message.content // empty' <<<"$resp" | llm_strip_think | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

llm_see_ollama() {
  local file=$1 prompt=$2 timeout=${3:-45}
  local tmp imgf jsonf resp
  ensure_ollama_server || return 1
  curl -sf --max-time 1 "$OLLAMA_HOST/api/tags" \
    | jq -e --arg m "$OLLAMA_VISION" '.models[]? | select(.name == $m or (.name | startswith($m)))' >/dev/null \
    || return 1
  tmp=$(mktemp --suffix=.jpg)
  magick "$file" -auto-orient -resize '768x768>' -strip -quality 75 "$tmp" 2>/dev/null || cp -- "$file" "$tmp"
  imgf=$(mktemp)
  jsonf=$(mktemp)
  base64 -w0 "$tmp" >"$imgf"
  rm -f "$tmp"
  jq -n \
    --arg model "$OLLAMA_VISION" \
    --arg prompt "$prompt" \
    --rawfile img "$imgf" \
    --arg keepalive "${VISION_KEEP_ALIVE}s" \
    '{model:$model, prompt:$prompt, images:[$img], stream:false, keep_alive:$keepalive, options:{temperature:0.1, num_predict:64, num_ctx:2048}}' \
    >"$jsonf"
  rm -f "$imgf"
  resp=$(curl -sf --max-time "$timeout" "$OLLAMA_HOST/api/generate" \
    -H 'Content-Type: application/json' \
    --data-binary @"$jsonf") || { rm -f "$jsonf"; abort_ollama_runner; return 1; }
  rm -f "$jsonf"
  jq -r '.response // empty' <<<"$resp"
}

llm_strip_fences() {
  sed -e 's/^```[a-zA-Z0-9]*[[:space:]]*//' -e 's/^```$//' | sed '/^```$/d'
}

llm_strip_think() {
  python3 -c '
import re, sys
t = sys.stdin.read()
t = re.sub(r"<think>.*?</think>", "", t, flags=re.S | re.I)
t = re.sub(r"<\|think\|>.*?<\|/think\|>", "", t, flags=re.S | re.I)
sys.stdout.write(t)
' 2>/dev/null || sed -e '/<think>/,/<\/think>/d' -e '/<|think|>/,/<|\/think|>/d'
}
