# ai-toolkit

A toolkit for holding AI **skills**, **agents**, **instructions**, and **MCP servers** —
reusable building blocks that make code-generating AI agents faster, safer, and consistent.

---

## What's inside

| Folder | Purpose |
| --- | --- |
| [`copilot/`](./copilot/) | A vendor-neutral, Java 21 / Spring Boot catalogue of **40 reusable coding-pattern skills**, **10 task agents**, an agent operating manual, and project documentation templates. |
| [`setup/`](./setup/) | Editor integration guides — how to wire the toolkit into your IDE (e.g. [`setup/jetbrains/`](./setup/jetbrains/) for JetBrains + GitHub Copilot). |

More toolsets (additional agent packs, MCP servers, editor instructions) will live
alongside `copilot/` as they are added.

---

## Quick start

### JetBrains + GitHub Copilot (global — works in every project)

Full setup guide: [`setup/jetbrains/README.md`](./setup/jetbrains/README.md)

```bash
# 1. Symlink the toolkit globally (run once)
ln -s /Users/odafna/repo/oriddd/ai-toolkit ~/.ai-toolkit

# 2. Paste the 2-line snippet into:
#    JetBrains → Settings → Tools → GitHub Copilot → Custom Instructions
#    (file: setup/jetbrains/copilot-global-instructions.md)
```

Then in any Copilot chat session, from any project:
```
#file ~/.ai-toolkit/copilot/public/skills/exception-handling/SKILL.md
Apply this skill to the current file.
```

Session-start cost: ~30 tokens. Skills are read only when you `#file` them.
See [`setup/jetbrains/cheatsheet.md`](./setup/jetbrains/cheatsheet.md) for ready-to-paste patterns.

### Use as a developer (no AI)
Start with [`copilot/HOW-TO.md`](./copilot/HOW-TO.md), then look up your task in
[`copilot/public/skills/INDEX_BY_USE_CASE.md`](./copilot/public/skills/INDEX_BY_USE_CASE.md).

### Bootstrap a new project's docs
Copy [`copilot/context/`](./copilot/context/) into your repo and fill in each template.

---

## Highlights

- **40 skills** across API design, persistence, messaging, observability, CI/CD, testing,
  security, resilience, and pluggable architecture.
- **24 non-negotiables** enforced on every diff (see
  [`copilot/public/skills/BACKEND_GUILD.md`](./copilot/public/skills/BACKEND_GUILD.md)).
- **10 focused agents** for common tasks (scaffold repo, new endpoint, new Kafka consumer, refactor, code review, …).
- **Fully validated** — run the checks below before any change.

```bash
cd copilot
python3 public/skills/build-indexes.py --check   # indexes in sync
bash public/skills/validate-skills.sh            # 40 skills lint clean
bash context/validate-context.sh          # context templates valid
```

---

## Contributing

See [`copilot/CONTRIBUTING.md`](./copilot/CONTRIBUTING.md). Keep skills **vendor-neutral** —
no org-specific terms, registries, or private libraries. Licensed under
[MIT](./copilot/LICENSE).

