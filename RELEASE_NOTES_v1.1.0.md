# v1.1.0 — Region picker, then FR↔EN

**Super+Shift+T** now uses the same freeze + rectangle as a screenshot. OCR, then Lemonade on the NPU. No more translating whatever happened to be on the clipboard.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.1

* **Super+Shift+T** → `omarchy-llm-translate --region`: freeze, draw a zone, Tesseract `eng+fra`, then FR↔EN. Esc cancels with no toast.
* Bind the new wrapper `omarchy-llm-translate-region` with `{ release = true }` so Super is up before slurp.
* Capture menu **Translate FR↔EN** uses `--region` as well.
* Default example model is **`qwen3.5-4b-FLM`** (one NPU slot for chat + vision). The picker honors that id even when Lemonade tags it `vision`.
* Still skip `qwen3-it:4b` on FastFlowLM 1.0.4.

Selection-only translate remains: `omarchy-llm-translate` without `--region`.

---

**📥 How to update?**
```sh
git -C ~/.config/omarchy/omarchy-translate pull
~/.config/omarchy/omarchy-translate/install.sh
# point Super+Shift+T at omarchy-llm-translate-region (hypr/bindings.lua.example)
hyprctl reload
omarchy restart shell
```

**📥 How to install?**
```sh
git clone https://github.com/austrasien/omarchy-translate.git ~/.config/omarchy/omarchy-translate
~/.config/omarchy/omarchy-translate/install.sh
# add Super+Shift+T from hypr/bindings.lua.example, then:
hyprctl reload
omarchy restart shell
```

💬 **Feedback:** Found a bug or have a suggestion? Open an [issue](https://github.com/austrasien/omarchy-translate/issues).
