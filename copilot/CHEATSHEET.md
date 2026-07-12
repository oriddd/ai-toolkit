# Toolkit Cheatsheet

The 30-second overview of what lives where and how to use it.
For deep-dives, follow the links — each area has its own cheatsheet next to it.

---

## Where things live

```
copilot/
├── public/
│   ├── skills/    → 45 atomic patterns + tooling   (see public/skills/CHEATSHEET.md)
│   └── agents/    → 10 task prompts + AGENT_PROMPT  (see public/agents/CHEATSHEET.md)
├── context/       → project doc templates + validate-context.sh
├── README.md      → platform overview
├── HOW-TO.md      → the full guide
└── CHEATSHEET.md  → you are here
```

**Co-location rule:** every tool sits next to what it serves — the skills
validator lives with the skills, the agent prompt lives with the agents, the
context validator lives with the context templates.

---

## Use it in your project (JetBrains + Copilot)

```bash
# once: symlink the toolkit globally
ln -s /path/to/ai-toolkit ~/.ai-toolkit
```

Then in any Copilot chat — load only what you need, when you need it:

```
# a single skill
#file ~/.ai-toolkit/copilot/public/skills/exception-handling/SKILL.md

# a task agent
#file ~/.ai-toolkit/copilot/public/agents/new-endpoint.md
```

Full setup: [`../setup/jetbrains/README.md`](../setup/jetbrains/README.md).

---

## Find the right thing

| I want to… | Go to |
| --- | --- |
| See every skill at a glance | [`public/skills/REGISTRY.md`](./public/skills/REGISTRY.md) |
| Find skills for a task | [`public/skills/INDEX_BY_USE_CASE.md`](./public/skills/INDEX_BY_USE_CASE.md) |
| Know what's mandatory | [`public/skills/BACKEND_GUILD.md`](./public/skills/BACKEND_GUILD.md) |
| Pick a task agent | [`public/agents/README.md`](./public/agents/README.md) |
| Author a skill | [`public/skills/AUTHORING.md`](./public/skills/AUTHORING.md) + [`public/skills/CHEATSHEET.md`](./public/skills/CHEATSHEET.md) |
| Author an agent | [`public/agents/CHEATSHEET.md`](./public/agents/CHEATSHEET.md) |
| Bootstrap project docs | [`context/`](./context/README.md) |

---

## Validate everything

```bash
cd copilot
bash public/skills/validate-skills.sh      # 45 skills lint clean
python3 public/skills/build-indexes.py --check   # indexes in sync
bash context/validate-context.sh           # context templates valid
```

