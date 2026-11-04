# JetBrains + GitHub Copilot Setup

Get the full ai-toolkit skills catalogue working in every JetBrains project —
zero per-project configuration, minimal token cost.

---

## How it works

```
~/.ai-toolkit/          ← symlink to this repo (single source of truth)
    plugins/*/skills/   ← skills grouped by phase/language, loaded only when you #file them
    plugins/*-agents/   ← task agents
    docs/               ← indexes (REGISTRY, INDEX_BY_USE_CASE), guild rules, guides

JetBrains global Copilot instructions  ← short routing pointer (≈150 tokens/session)
```

Skills are **never preloaded**. You pull one in with `#file` only when you
need it. Session-start cost is just the short pointer.

---

## Step 1 — Symlink the toolkit globally

Run once, from anywhere:

```bash
ln -s /path/to/ai-toolkit ~/.ai-toolkit
```

Verify:
```bash
ls ~/.ai-toolkit/plugins/*/skills | head -5
```

---

## Step 2 — Register the global Copilot instructions in JetBrains

1. Open any JetBrains IDE (IntelliJ IDEA, GoLand, PyCharm, etc.)
2. Go to **Settings → Tools → GitHub Copilot → Custom Instructions**
3. Paste the contents of [`copilot-global-instructions.md`](./copilot-global-instructions.md)
4. Click **OK**

That's it — applies to every project, every session automatically.

> **Note:** The custom instructions field is per-IDE installation, so repeat
> Step 2 once for each JetBrains IDE you use (IDEA, GoLand, etc.).

---

## Step 3 — Use skills in Copilot chat

See [`cheatsheet.md`](./cheatsheet.md) for ready-to-paste chat patterns.

Quick examples:

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
Apply this skill to the code in the current file.
```

```
#file ~/.ai-toolkit/docs/agents/AGENT_PROMPT.md
#file ~/.ai-toolkit/docs/BACKEND_GUILD.md
Add a new REST endpoint for creating an order.
```

---

## Updating the toolkit

Because `~/.ai-toolkit` is a symlink to your local repo, pulling updates
is automatic — just `git pull` in the ai-toolkit repo. No reinstall needed.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `~/.ai-toolkit` not found | Re-run: `ln -s /path/to/ai-toolkit ~/.ai-toolkit` |
| JetBrains doesn't see the instructions | Confirm the setting was saved in the correct IDE (each IDE has its own settings) |
| `#file` path not resolving | Use the full expanded path: `/Users/<you>/.ai-toolkit/...` instead of `~/...` |
| Skill file not found | Run `ls ~/.ai-toolkit/plugins/*/skills` (or look the skill up in `docs/REGISTRY.md`) to check available skills |

