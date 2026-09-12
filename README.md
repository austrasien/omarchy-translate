# Omarchy Translate (FR↔EN)

Select text anywhere, hit **Super+Shift+T**, get a French↔English translation from **Lemonade on the NPU**. The result lands on the clipboard and in a toast that can actually show the whole sentence.

> **⚡ Built for Omarchy:** a translation pipeline plus a clone of stock `omarchy.notifications`. Tall / sticky toasts apply **only** to this translator. Everything else keeps the 3-line clamp.

```
Selection  →  Super+Shift+T  →  Lemonade (NPU queue)  →  clipboard + toast
```

Two plugins in one repo (`austraz.translate` + `austraz.notifications`). `omarchy plugin add` installs a single `manifest.json`, so this bundle uses `./install.sh`.

---

### ☕ Support the Project
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

### 💬 Feedback & Community
Got a question, found a bug, or have a suggestion? Open an [**issue**](https://github.com/austrasien/omarchy-translate/issues).

---

## 🚀 Overview

Omarchy already has screenshots, OCR, and notifications. This repo wires a **one-shot translator** onto that stack without stealing the NPU from a vision job that is already loaded.

**Why bother?**

| | Stock Omarchy ❌ | This bundle ✅ |
| :--- | :--- | :--- |
| **Translate a selection** | No | **Super+Shift+T** (fires on key *release*) |
| **Engine** | — | Lemonade on the NPU, shared lock with screenshot naming |
| **Toast body** | 3 lines, 5–8s | Translation: **full body**, **3s per line**, **sticky if >3 lines** |
| **Other apps’ toasts** | Stock | Unchanged |
| **Omarchy** | Built-in notifications | User clone; disable `omarchy.notifications` |

> **Note:** Nothing from your notes or `llm.conf` is committed here. Copy `austraz.translate/llm/llm.conf.example` to `~/.config/omarchy/llm.conf` and set model ids locally.

## What’s inside

| Piece | Role |
| :--- | :--- |
| `austraz.translate/llm/translate.sh` | Grab selection, detect FR/EN, chat, copy, notify |
| `austraz.translate/llm/lib.sh` | Lemonade client, NPU slot, **never evict a foreign model** |
| `austraz.translate/bin/omarchy-llm-translate` | PATH wrapper (`~/.config/omarchy/bin/`) |
| `austraz.notifications/` | Clone of `omarchy.notifications` — full body + custom lifetime **only** for `app=austraz.translate` |
| `austraz.translate/Overlay.qml` | Optional cursor chip (`--menu`). **Leave disabled** |

## ✨ Key Features

### ⌨️ Super+Shift+T
- Copies the highlight (Wayland primary, then Ctrl+C / Ctrl+Insert in terminals tagged `terminal`).
- Hyprland binds attach `/dev/null` as stdin — the script does **not** treat that as source text.
- Bind must use `{ release = true }` so Super is up before injecting Ctrl+C ([Hyprland #14099](https://github.com/hyprwm/Hyprland/issues/14099); Electron has no Wayland primary).
- Hard kill at **30s**. Progress toast stays until the result replaces it.

### 🧠 FR↔EN, not paraphrase
- Detects source language and wraps an explicit EN→FR or FR→EN prompt.
- Same-language reply retries once.
- Prefers a small text model; **skips `qwen3-it:4b`** (FastFlowLM 1.0.4 aborts on empty logits). Falls back to a VL id such as `qwen3vl-it-4b-FLM` when no safe text model is loaded.

### 🔔 Toasts (translate only)
- `--app-name austraz.translate`, titles **Translation** / **Translation copied**.
- **3s per visual line** (~42 columns). More than three lines → **critical** (stays until you dismiss).
- Other notifications keep stock duration and the 3-line clamp.

### 🔒 NPU queue
- Shares `${XDG_RUNTIME_DIR}/image-autoname.lock`.
- If another model occupies the slot, the job waits or bails with “NPU occupé” — it does **not** unload a model it did not load.

## 🛠 Installation

Lemonade must already answer on `http://127.0.0.1:13305` (or set `LEMONADE_HOST` in `~/.config/omarchy/llm.conf`).

```sh
git clone https://github.com/austrasien/omarchy-translate.git ~/.config/omarchy/omarchy-translate
~/.config/omarchy/omarchy-translate/install.sh
```

`install.sh` symlinks both plugins into `~/.config/omarchy/plugins/`, puts `omarchy-llm-translate` on `~/.config/omarchy/bin`, enables `austraz.notifications`, disables stock `omarchy.notifications`, and **leaves the overlay disabled**.

Then add the bind to `~/.config/hypr/bindings.lua` (see `hypr/bindings.lua.example`):

```lua
o.bind(
  "SUPER + SHIFT + T",
  "Translate selection",
  os.getenv("HOME") .. "/.config/omarchy/bin/omarchy-llm-translate",
  { release = true }
)
```

Reload Hyprland and the shell:

```sh
hyprctl reload
omarchy restart shell
```

Optional: Omarchy menu entry **Trigger → Capture → Translate FR↔EN** with action `omarchy-llm-translate`.

### Why not `omarchy plugin add`?

That command clones **one** git URL into **one** plugin folder that must contain `manifest.json` at the root. This repo is a **bundle of two** plugins. Use `install.sh`. Updating:

```sh
git -C ~/.config/omarchy/omarchy-translate pull
omarchy restart shell
```

### Update / remove

```sh
git -C ~/.config/omarchy/omarchy-translate pull
# remove:
omarchy plugin disable austraz.notifications
omarchy plugin enable omarchy.notifications
rm -f ~/.config/omarchy/plugins/austraz.translate \
      ~/.config/omarchy/plugins/austraz.notifications \
      ~/.config/omarchy/bin/omarchy-llm-translate
omarchy restart shell
```

## ⚙️ Settings

`~/.config/omarchy/llm.conf` (sourced by `lib.sh`; never committed):

| Key | Default | Meaning |
|---|---|---|
| `LEMONADE_HOST` | `http://127.0.0.1:13305` | Lemonade API |
| `LLM_TEXT_SMALL` | `llama3.2-3b-FLM` | Preferred small chat id (download it, or a VL fallback is used) |
| `LLM_VISION` | `qwen3vl-it-4b-FLM` | Fallback when no safe text model is loaded |
| `VISION_KEEP_ALIVE` | `300` | Seconds before idle unload of a model **we** loaded |

Do **not** set `qwen3-it:4b` / `qwen3-it-4b-FLM` — FastFlowLM 1.0.4 SIGABRTs on that family.

## Verify

1. Highlight a French sentence in a browser or terminal → **Super+Shift+T** (release the keys) → toast **Translation** then **Translation copied**; clipboard has English.
2. Highlight English → same bind → French in the toast.
3. More than three wrapped lines → toast stays until you right-click dismiss.
4. A Discord / volume toast still clamps to three lines and expires as before.

## ⚖️ License

**MIT** — see [LICENSE](LICENSE). Notifications UI is a fork of Omarchy’s `omarchy.notifications`; see [NOTICE](NOTICE).

---
*Developed so Super+Shift+T translates the selection on the NPU — without flattening every other Omarchy toast.*
