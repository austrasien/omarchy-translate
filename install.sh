#!/usr/bin/env bash
# Install both plugins from this meta-repo. `omarchy plugin add` cannot load
# two manifests from one git root — run this instead.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
PLUGINS="$CONFIG/plugins"
BIN="$CONFIG/bin"

mkdir -p "$PLUGINS" "$BIN"

link_plugin() {
  local id=$1
  local dest="$PLUGINS/$id"
  local src="$ROOT/$id"
  [[ -d $src ]] || { echo "missing $src" >&2; exit 1; }
  if [[ -L $dest || -e $dest ]]; then
    rm -rf "$dest"
  fi
  ln -sfn "$src" "$dest"
  echo "linked $dest -> $src"
}

link_plugin austraz.translate
link_plugin austraz.notifications

chmod +x \
  "$ROOT/austraz.translate/bin/omarchy-llm-translate" \
  "$ROOT/austraz.translate/bin/omarchy-llm-translate-region" \
  "$ROOT/austraz.translate/llm/translate.sh" \
  "$ROOT/austraz.translate/capture-primary.sh" \
  "$ROOT/austraz.notifications/copy-to-clipboard.sh"

ln -sfn "$PLUGINS/austraz.translate/bin/omarchy-llm-translate" \
  "$BIN/omarchy-llm-translate"
ln -sfn "$PLUGINS/austraz.translate/bin/omarchy-llm-translate-region" \
  "$BIN/omarchy-llm-translate-region"
chmod +x "$BIN/omarchy-llm-translate" "$BIN/omarchy-llm-translate-region"
echo "linked $BIN/omarchy-llm-translate{,-region}"

if [[ ! -f $CONFIG/llm.conf ]]; then
  cp "$ROOT/austraz.translate/llm/llm.conf.example" "$CONFIG/llm.conf"
  echo "wrote $CONFIG/llm.conf from example — edit model ids if needed"
else
  echo "kept existing $CONFIG/llm.conf"
fi

if command -v omarchy >/dev/null; then
  omarchy plugin enable austraz.notifications >/dev/null || true
  omarchy plugin disable omarchy.notifications >/dev/null || true
  omarchy plugin disable austraz.translate >/dev/null || true
  echo "enabled austraz.notifications; overlay austraz.translate left disabled"
fi

cat <<'EOF'

Next:

1. Bind Super+Shift+T to omarchy-llm-translate-region (see hypr/bindings.lua.example).
   Fire on key *release* so Super is up before the region picker.
2. Lemonade must be reachable (default http://127.0.0.1:13305). Needs tesseract (eng+fra).
3. Restart the shell so the notifications clone is keepLoaded:

   omarchy restart shell

Do not enable austraz.translate unless you want the optional overlay chip.
EOF
