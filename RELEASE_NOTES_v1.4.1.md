# v1.4.1 — Reasoning that stays where you put it

FastFlowLM does not decide reasoning per request: it keeps a **global switch** set by the last request. One quick script sending `enable_thinking: false` (translate does, to stay fast) turned reasoning off for your next chat and your coding agent, until something sent `think: true` again.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you a round-trip through a browser translator, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s new in 1.4.1

* `npu-queue` learns `NPU_QUEUE_THINK=on|off|keep` (default `keep`, nothing changes).
* With `on`, every request gets an explicit `think`: `false` only when it asks for no reasoning (`enable_thinking`, `thinking` or `think` false, `thinking.type: disabled`), `true` otherwise. Scripts stay fast, chats and agents keep reasoning.
* Lemonade ignores `think` on `/v1/messages` (Claude Code and other Anthropic clients), so the queue flips the switch with a 1-token chat request first — only when it is in the wrong position.
* `X-NPU-Think: on|off` forces it for one request, and so does a model id ending in `:nothink` / `:think` (the suffix is stripped before Lemonade sees it).
* Example: Claude Code generates session titles and away summaries with its Haiku model. `ANTHROPIC_DEFAULT_HAIKU_MODEL=<model>:nothink` keeps those at a few seconds instead of a minute and a half of reasoning, while the main model keeps thinking.

```ini
# systemctl --user edit npu-queue.service
[Service]
Environment=NPU_QUEUE_THINK=on
```

---

**📥 How to update?**
```sh
git -C ~/.config/omarchy/omarchy-translate pull
~/.config/omarchy/omarchy-translate/install.sh
systemctl --user restart npu-queue.service
```

MIT — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
