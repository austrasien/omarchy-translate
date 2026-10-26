# v1.4.0 — One queue for the NPU

Translate, screenshot naming, a local coding agent and the Lemonade app all share **one model on one NPU**. When they fired at the same time, the slow ones timed out — and FastFlowLM kept computing the request nobody was waiting for anymore. This release adds an optional queue that hands the NPU to one job at a time.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.4

* **`npu-queue`** (optional, off by default): a small proxy on `127.0.0.1:13306` in front of Lemonade. Inference requests wait their turn; everything else passes straight through.
* **Priorities**: `interactive` (translate) > `agent` (coding agents, the Lemonade app) > `background`. FIFO within a level, the running request is never interrupted.
* **No ghost requests**: a client that gives up while waiting is removed before it reaches the NPU.
* **Bounded waits**: `503` after `LLM_QUEUE_WAIT` (shown as **NPU occupé**), `504` if the backend goes silent for 10 minutes, so a hung FastFlowLM no longer freezes every tool.
* Translate shows **en file d'attente (N devant)** when the NPU is taken, then finishes on its own.
* `npu-queue status` lists what runs and who waits.
* `austraz.notifications` is now **1.0.6**: left-click a Taildrop toast to open the received file.

With `LLM_QUEUE_WAIT=0` (the default) `lib.sh` behaves exactly as in 1.3.

---

**🚦 How to enable the queue?**
```sh
systemctl --user link ~/.config/omarchy/plugins/austraz.translate/systemd/npu-queue.service
systemctl --user enable --now npu-queue.service
# ~/.config/omarchy/llm.conf
LEMONADE_HOST=http://127.0.0.1:13306
LLM_QUEUE_WAIT=600
```

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
