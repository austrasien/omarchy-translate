# v1.0.0 — Translate FR↔EN on Super+Shift+T

Select text, release **Super+Shift+T**, get a French↔English translation from Lemonade on the NPU. The toast can show the whole result; other apps keep stock Omarchy notifications.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.0

* **Super+Shift+T** copies the selection (primary, then Ctrl+C / Ctrl+Insert in terminals) and translates FR↔EN. Bind fires on **release** so Super is up before the copy inject.
* Lemonade on the NPU, **30s** hard timeout, shared `image-autoname` lock — **never evicts** a model it did not load.
* Explicit EN→FR / FR→EN prompts (no English paraphrase). Same-language reply retries once.
* Progress toast stays until the result replaces it (`app-name austraz.translate`).
* **3s per visual line**; **more than 3 lines → sticky** (dismiss yourself). Errors ~8s.
* `austraz.notifications` clone: full body + custom lifetime **only** for translation toasts. Everything else stays the 3-line / 5–8s stock behavior.
* Overlay chip ships but stays **disabled** — Super+Shift+T is the UX.
* Avoid `qwen3-it:4b` on FastFlowLM 1.0.4 (empty logits abort).

This is a **two-plugin bundle**. `omarchy plugin add` cannot install both from one git root — use `install.sh`.

---

**📥 How to install?**
```sh
git clone https://github.com/austrasien/omarchy-translate.git ~/.config/omarchy/omarchy-translate
~/.config/omarchy/omarchy-translate/install.sh
# add Super+Shift+T from hypr/bindings.lua.example, then:
hyprctl reload
omarchy restart shell
```

**📥 How to update?**
```sh
git -C ~/.config/omarchy/omarchy-translate pull
omarchy restart shell
```

💬 **Feedback:** Found a bug or have a suggestion? Open an [issue](https://github.com/austrasien/omarchy-translate/issues).
