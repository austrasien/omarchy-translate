# Omarchy Translate (FR↔EN)

Hit **Super+Shift+T**, draw a rectangle (same freeze as a screenshot), get a French↔English translation from **Lemonade on the NPU**. The result lands on the clipboard and in a toast that can actually show the whole sentence.

> **⚡ Built for Omarchy:** a translation pipeline plus a clone of stock `omarchy.notifications`. Tall / sticky toasts apply **only** to this translator. Everything else keeps the 3-line clamp.

```
Super+Shift+T  →  freeze + region  →  OCR  →  Lemonade (NPU queue)  →  clipboard + toast
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
| **Translate a screen region** | No | **Super+Shift+T** — freeze + rectangle, then OCR (fires on key *release*) |
| **Engine** | — | Lemonade on the NPU, shared lock with screenshot naming |
| **Toast body** | 3 lines, 5–8s | Translation: **full body**, **3s per line**, **sticky if >3 lines** |
| **Other apps’ toasts** | Stock | Unchanged |
| **Omarchy** | Built-in notifications | User clone; disable `omarchy.notifications` |

> **Note:** Nothing from your notes or `llm.conf` is committed here. Copy `austraz.translate/llm/llm.conf.example` to `~/.config/omarchy/llm.conf` and set model ids locally.

## What’s inside

| Piece | Role |
| :--- | :--- |
| `austraz.translate/llm/translate.sh` | `--region`: slurp + OCR; else clipboard selection; detect FR/EN, chat, copy, notify |
| `austraz.translate/llm/lib.sh` | Lemonade client, NPU slot, **never evict a foreign model** |
| `austraz.translate/bin/omarchy-llm-translate-region` | PATH wrapper for Super+Shift+T (`--region`) |
| `austraz.translate/bin/omarchy-llm-translate` | PATH wrapper without `--region` (selection / `--file`) |
| `austraz.translate/bin/npu-queue` | **Optional** priority queue in front of Lemonade: one inference at a time on the NPU (`systemd/npu-queue.service`) |
| `austraz.notifications/` | Clone of `omarchy.notifications` — full body + custom lifetime **only** for `app=austraz.translate`; right-click a **Screenshot renamed** toast copies the image |
| `austraz.translate/Overlay.qml` | Optional cursor chip (`--menu`). **Leave disabled** |

## ✨ Key Features

### ⌨️ Super+Shift+T
- Same freeze + rectangle as **Impr. écran** (`omarchy-capture-region`), then Tesseract `eng+fra`, then FR↔EN.
- Bind `omarchy-llm-translate-region` with `{ release = true }` so Super is up before slurp (Super+drag would move windows).
- Esc cancels with no toast. Empty OCR → **Aucun texte dans la zone**.
- `omarchy-llm-translate` without `--region` still translates a text selection / `--file`.
- Hard kill at **30s**. Progress toast stays until the result replaces it (after the picker, not during).

### 🧠 FR↔EN, not paraphrase
- Detects source language and wraps an explicit EN→FR or FR→EN prompt.
- Same-language reply retries once.
- Prefers `qwen3.5-4b-FLM` (one NPU slot for chat + vision). **Skips `qwen3-it:4b`** (FastFlowLM 1.0.4 aborts on empty logits).

### 🔔 Toasts (translate only)
- `--app-name austraz.translate`, titles **Translation** / **Translation copied**.
- **3s per visual line** (~42 columns). More than three lines → **critical** (stays until you dismiss).
- Other notifications keep stock duration and the 3-line clamp.
- Toasts only appear on the **built-in screen** (`eDP-*`), never on external monitors. With the lid closed (no `eDP` output), they fall back to every screen.
- **Screenshot renamed** (from [image-autoname](https://github.com/austrasien/omarchy-image-autoname)): left-click opens the editor; **right-click copies the PNG** to the clipboard, then dismisses. Other toasts still just close on right-click.

### 🔒 NPU queue
- Shares `${XDG_RUNTIME_DIR}/image-autoname.lock`.
- If another model occupies the slot, the job waits or bails with “NPU occupé” — it does **not** unload a model it did not load.

### 🚦 Optional: `npu-queue`
When several tools share one model (translate, screenshot naming, a local coding agent, the Lemonade app…), they all hit the NPU at once and the slow ones time out — while FastFlowLM keeps computing the abandoned request. `npu-queue` sits on `127.0.0.1:13306` in front of Lemonade (`13305`):

- **One inference at a time.** Chat / messages / completions wait in a queue; `/health`, `/models`, `/load`… pass straight through.
- **Priorities** via the `X-NPU-Priority` header: `interactive` (translate) > `agent` (default: coding agents, the Lemonade app) > `background`. FIFO within a level; the running request is never preempted.
- **No ghost requests.** A client that gives up while waiting is dropped before it reaches the NPU.
- **Bounded.** `X-NPU-Max-Wait` (default 600 s) → `503`, which `lib.sh` reports as “NPU occupé”. A backend silent for 600 s → `504`, and the queue moves on.
- `npu-queue status` shows what runs and who waits. Python standard library only.

Enable it (install.sh links the binary but does not start it):

```sh
systemctl --user link ~/.config/omarchy/plugins/austraz.translate/systemd/npu-queue.service
systemctl --user enable --now npu-queue.service
```

Then set `LEMONADE_HOST=http://127.0.0.1:13306` and `LLM_QUEUE_WAIT=600` in `~/.config/omarchy/llm.conf`. Point other clients at `13306` too (Lemonade app: *Settings → Base URL*; Claude Code: `ANTHROPIC_BASE_URL`); anything that still calls `13305` bypasses the queue.

## 🛠 Installation

Lemonade must already answer on `http://127.0.0.1:13305` (or set `LEMONADE_HOST` in `~/.config/omarchy/llm.conf`).

```sh
git clone https://github.com/austrasien/omarchy-translate.git ~/.config/omarchy/omarchy-translate
~/.config/omarchy/omarchy-translate/install.sh
```

`install.sh` symlinks both plugins into `~/.config/omarchy/plugins/`, puts `omarchy-llm-translate` and `omarchy-llm-translate-region` on `~/.config/omarchy/bin`, enables `austraz.notifications`, disables stock `omarchy.notifications`, and **leaves the overlay disabled**.

Then add the bind to `~/.config/hypr/bindings.lua` (see `hypr/bindings.lua.example`):

```lua
o.bind(
  "SUPER + SHIFT + T",
  "Translate region",
  os.getenv("HOME") .. "/.config/omarchy/bin/omarchy-llm-translate-region",
  { release = true }
)
```

Reload Hyprland and the shell:

```sh
hyprctl reload
omarchy restart shell
```

Optional: Omarchy menu **Trigger → Capture → Translate FR↔EN** with action `omarchy-llm-translate --region`.

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
      ~/.config/omarchy/bin/omarchy-llm-translate \
      ~/.config/omarchy/bin/omarchy-llm-translate-region
omarchy restart shell
```

## 🧾 Changelog

### v1.4.0
- Optional **`npu-queue`**: priority queue in front of Lemonade, one NPU inference at a time, waiting clients dropped before they reach the NPU, `npu-queue status`.
- `lib.sh` talks to it when `LLM_QUEUE_WAIT > 0`: sends its priority, waits up to `LLM_QUEUE_WAIT`, maps `503` to “NPU occupé”, releases the shared lock before queueing. Translate runs as `interactive` and toasts **en file d'attente (N devant)** when it has to wait. With `LLM_QUEUE_WAIT=0` (default) nothing changes.
- `austraz.notifications` **1.0.6**: left-click a Taildrop toast opens the received file.

### v1.3.0
- Notification popups show on the built-in screen (`eDP-*`) only. External monitors stay clean. With no `eDP` output (lid closed), they fall back to every screen.

### v1.2.0
- Right-click a **Screenshot renamed** (or stock **Screenshot saved**) toast to copy the image pixels, then dismiss. Needs `copy-to-clipboard.sh` next to the plugin (install.sh chmods it).
- Cursor CLI toasts (`org.omarchy.agent`) use the launcher cube instead of Qt’s missing-texture square, when `~/.local/share/pixmaps/cursor-cli.png` exists.

### v1.1.0
- **Super+Shift+T** draws a screenshot region (freeze + slurp), OCRs it (`eng+fra`), then translates. Bind `omarchy-llm-translate-region`.
- Default Lemonade id in the example conf is `qwen3.5-4b-FLM` (one slot for chat + vision). Picker honors that id even when Lemonade tags it `vision`.

### v1.0.1
- Fix `austraz.notifications` failing to load (`NotificationCard.qml` duplicate `Layout.preferredHeight`), which broke all desktop notifications including low-battery alerts. Translation toast `expandBody` behavior is unchanged.

## ⚙️ Settings

`~/.config/omarchy/llm.conf` (sourced by `lib.sh`; never committed):

| Key | Default | Meaning |
|---|---|---|
| `LEMONADE_HOST` | `http://127.0.0.1:13305` | Lemonade API |
| `LLM_TEXT_SMALL` | `qwen3.5-4b-FLM` | Preferred chat id (multimodal; one NPU slot with vision) |
| `LLM_VISION` | `qwen3.5-4b-FLM` | Same family so screenshot naming and translate do not swap models |
| `VISION_KEEP_ALIVE` | `300` | Seconds before idle unload of a model **we** loaded |
| `LLM_QUEUE_WAIT` | `0` | Seconds a job may wait in `npu-queue` (`0` = no queue, direct Lemonade) |
| `LLM_PRIORITY` | `background` | Queue priority for callers of `lib.sh` (translate sets `interactive`) |

Do **not** set `qwen3-it:4b` / `qwen3-it-4b-FLM` — FastFlowLM 1.0.4 SIGABRTs on that family.

## Verify

1. **Super+Shift+T** (release the keys) → screen freezes → draw a rectangle over French text → toast **Translation copied** with English; clipboard matches.
2. Same over English → French in the toast.
3. Esc on the picker → nothing (no toast).
4. More than three wrapped lines → toast stays until you right-click dismiss.
5. A Discord / volume toast still clamps to three lines and expires as before.
6. After [image-autoname](https://github.com/austrasien/omarchy-image-autoname) renames a capture: left-click the toast opens the editor; right-click copies the image (paste into a chat to check).

## ⚖️ License

**MIT** — see [LICENSE](LICENSE). Notifications UI is a fork of Omarchy’s `omarchy.notifications`; see [NOTICE](NOTICE).

---
*Developed so Super+Shift+T translates a screen region on the NPU — without flattening every other Omarchy toast.*
