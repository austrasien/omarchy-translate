# v1.3.0 — Toasts on the built-in screen only

The notifications clone used to draw every toast on every monitor. It now keeps them on the **laptop panel** and leaves external screens alone.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.3

* Popups only open on outputs named `eDP-*` (the built-in display). A presentation or a video on the external monitor is no longer covered by toasts.
* With the lid closed and no `eDP` output, toasts fall back to every screen, so they never disappear entirely.
* `austraz.notifications` is now **1.0.5**.

---

**📥 How to update?**
```sh
git -C ~/.config/omarchy/omarchy-translate pull
~/.config/omarchy/omarchy-translate/install.sh
omarchy restart shell
```

**📥 How to install?**
```sh
git clone https://github.com/austrasien/omarchy-translate.git ~/.config/omarchy/omarchy-translate
~/.config/omarchy/omarchy-translate/install.sh
omarchy restart shell
```

MIT — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
