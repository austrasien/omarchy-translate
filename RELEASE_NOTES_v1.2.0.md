# v1.2.0 — Right-click copies the renamed screenshot

The notifications clone already showed the full translation. It now also **copies the PNG** when you right-click a screenshot toast from [image-autoname](https://github.com/austrasien/omarchy-image-autoname).

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.2

* **Screenshot renamed** / **Screenshot saved** toasts: left-click still opens the editor; **right-click copies the image pixels** to the clipboard, then dismisses.
* Other toasts keep the stock right-click (dismiss only).
* Cursor CLI toasts (`org.omarchy.agent`) use the launcher cube when `~/.local/share/pixmaps/cursor-cli.png` is present, instead of Qt’s missing-texture square.

Needs [image-autoname v1.2](https://github.com/austrasien/omarchy-image-autoname/releases/tag/v1.2) for the rename toast itself.

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
