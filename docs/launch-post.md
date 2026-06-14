# Launch post (LinkedIn) — draft

> Draft copy for announcing Recall. Tweak freely before posting.

---

I built a tiny tool because Claude Code kept making me lose my place. Meet **Recall**. 👇

It started with a very specific annoyance: I'd ask Claude Code for something, it'd take a bit to respond, so I'd switch to another task… and then completely miss when it finished. Classic context-switch black hole.

So I wired up macOS notifications for Claude Code. Better — now I knew when it needed me.

But a new problem showed up. I run *a lot* of Claude sessions, scattered across terminal tabs and VSCode windows. A notification would fire… and clicking it didn't take me back to the *specific* terminal that sent it. I'd still be hunting through windows trying to find which session pinged me.

So I fixed that too.

**Recall** makes the notification click land you in the exact terminal — right window, right tab — that Claude was working in. No more hunting.

It's open source (MIT), for macOS + VSCode + Claude Code:

```
curl -fsSL https://raw.githubusercontent.com/alielzei/recall/main/install.sh | bash
```

→ github.com/alielzei/recall

If you run Claude Code across a bunch of terminals, this'll save you the "wait, which one was it?" dance.
