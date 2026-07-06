# ai-toolkit

A toolkit for holding AI **skills**, **agents**, **instructions**, and **MCP servers** —
reusable building blocks that make code-generating AI agents faster, safer, and consistent.

---

## What's inside

| Folder | Purpose |
| --- | --- |
| [`copilot/`](./copilot/) | A vendor-neutral, Java 21 / Spring Boot catalogue of **40 reusable coding-pattern skills**, **7 task agents**, an agent operating manual, and project documentation templates. |

More toolsets (additional agent packs, MCP servers, editor instructions) will live
alongside `copilot/` as they are added.

---

## Quick start

### Use with an AI coding agent
Paste [`copilot/skills/AGENT_PROMPT.md`](./copilot/skills/AGENT_PROMPT.md) into your
agent's system prompt (GitHub Copilot, Cursor, Claude, etc.). The agent then
autonomously selects and applies the right skills for every task.

### Use as a developer
Start with [`copilot/HOW-TO.md`](./copilot/HOW-TO.md), then look up your task in
[`copilot/skills/INDEX_BY_USE_CASE.md`](./copilot/skills/INDEX_BY_USE_CASE.md).

### Bootstrap a new project's docs
Copy [`copilot/context/`](./copilot/context/) into your repo and fill in each template.

---

## Highlights

- **40 skills** across API design, persistence, messaging, observability, CI/CD, testing,
  security, resilience, and pluggable architecture.
- **24 non-negotiables** enforced on every diff (see
  [`copilot/skills/BACKEND_GUILD.md`](./copilot/skills/BACKEND_GUILD.md)).
- **7 focused agents** for common tasks (new endpoint, new feature, code review, …).
- **Fully validated** — run the checks below before any change.

```bash
cd copilot
python3 skills/build-indexes.py --check   # indexes in sync
bash skills/validate-skills.sh            # 40 skills lint clean
bash context/validate-context.sh          # context templates valid
```

---

## Contributing

See [`copilot/CONTRIBUTING.md`](./copilot/CONTRIBUTING.md). Keep skills **vendor-neutral** —
no org-specific terms, registries, or private libraries. Licensed under
[MIT](./copilot/LICENSE).

