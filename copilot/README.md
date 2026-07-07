# Copilot — Skills, Agents & Context Platform

A vendor-neutral, Java 21 / Spring Boot catalogue of **reusable coding patterns**
(Skills) and **project documentation templates** (Context), designed to be dropped
into any code-generating AI agent's system prompt or used directly by developers.

---

## What's inside

| Folder / File | Purpose |
| --- | --- |
| [`public/skills/`](./public/skills/README.md) | 40 atomic skills covering every layer of a microservice — API design, persistence, messaging, observability, CI/CD, testing, and more. |
| [`public/agents/`](./public/agents/README.md) | 10 task-focused agent prompts that compose skills for a single job (scaffold a repo, add an endpoint, add a Kafka consumer, code review, refactor, …). |
| [`AGENT_PROMPT.md`](./public/agents/AGENT_PROMPT.md) | **Drop this into your agent's system prompt.** Operating manual that turns the catalogue into autonomous agent behaviour. |
| [`BACKEND_GUILD.md`](./public/skills/BACKEND_GUILD.md) | Adoption matrix (MUST / SHOULD / MAY), apply-order, task-driven recipes, and 24 non-negotiables. |
| [`REGISTRY.md`](./public/skills/REGISTRY.md) | Machine-readable index of every skill with frontmatter. |
| [`INDEX_BY_USE_CASE.md`](./public/skills/INDEX_BY_USE_CASE.md) | Reverse-lookup: "I want to do X" → which skills to read. |
| [`AUTHORING.md`](./public/skills/AUTHORING.md) | How to write and validate a new skill. |
| [`context/`](./context/README.md) | Documentation templates for a project's living context (architecture, SLOs, runbooks, glossary, etc.). Fill these in per-project. |
| [`CHEATSHEET.md`](./CHEATSHEET.md) | 30-second overview of what lives where and how to use it. |
| [`HOW-TO.md`](./HOW-TO.md) | The full usage guide. |
| [`CHANGELOG.md`](./CHANGELOG.md) | History of changes to this catalogue. |

---

## Quick start

### 1. Use with an AI coding agent

Paste the contents of [`AGENT_PROMPT.md`](./public/agents/AGENT_PROMPT.md) into
your agent's system prompt (GitHub Copilot instructions, Cursor rules, etc.).
The agent will then autonomously select and apply the right skills for every task.

### 2. Use manually as a developer

1. Identify your task in [`INDEX_BY_USE_CASE.md`](./public/skills/INDEX_BY_USE_CASE.md).
2. Read the relevant `public/skills/<name>/SKILL.md` files.
3. Copy any scaffold files from `public/skills/<name>/templates/` and substitute
   `{{placeholder}}` tokens.

### 3. Bootstrap a new project's context

Copy the `context/` folder into your new repository and fill in each template.
Run `bash context/validate-context.sh` to verify required sections are populated.

---

## Validation

```bash
# Validate all 40 skills (frontmatter, links, template references)
bash public/skills/validate-skills.sh

# Validate project context files (required sections are non-empty)
bash context/validate-context.sh

# Rebuild REGISTRY.md and BACKEND_GUILD.md from frontmatter
python3 public/skills/build-indexes.py
```

---

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). The short version:
- Keep skills **vendor-neutral** — no org-specific terms, registries, or libraries.
- Run `bash public/skills/validate-skills.sh` before submitting.
- Follow the authoring contract in [`AUTHORING.md`](./public/skills/AUTHORING.md).

