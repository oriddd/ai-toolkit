# Copilot — Skills & Context Platform

A vendor-neutral, Java 21 / Spring Boot catalogue of **reusable coding patterns**
(Skills) and **project documentation templates** (Context), designed to be dropped
into any code-generating AI agent's system prompt or used directly by developers.

---

## What's inside

| Folder / File | Purpose |
| --- | --- |
| [`skills/`](./skills/README.md) | 40 atomic skills covering every layer of a microservice — API design, persistence, messaging, observability, CI/CD, testing, and more. |
| [`skills/AGENT_PROMPT.md`](./skills/AGENT_PROMPT.md) | **Drop this into your agent's system prompt.** Operating manual that turns the catalogue into autonomous agent behaviour. |
| [`skills/BACKEND_GUILD.md`](./skills/BACKEND_GUILD.md) | Adoption matrix (MUST / SHOULD / MAY), apply-order, task-driven recipes, and 24 non-negotiables. |
| [`skills/REGISTRY.md`](./skills/REGISTRY.md) | Machine-readable index of every skill with frontmatter. |
| [`skills/INDEX_BY_USE_CASE.md`](./skills/INDEX_BY_USE_CASE.md) | Reverse-lookup: "I want to do X" → which skills to read. |
| [`skills/AUTHORING.md`](./skills/AUTHORING.md) | How to write and validate a new skill. |
| [`context/`](./context/README.md) | Documentation templates for a project's living context (architecture, SLOs, runbooks, glossary, etc.). Fill these in per-project. |
| [`CHANGELOG.md`](./CHANGELOG.md) | History of changes to this catalogue. |

---

## Quick start

### 1. Use with an AI coding agent

Paste the contents of [`skills/AGENT_PROMPT.md`](./skills/AGENT_PROMPT.md) into
your agent's system prompt (GitHub Copilot instructions, Cursor rules, etc.).
The agent will then autonomously select and apply the right skills for every task.

### 2. Use manually as a developer

1. Identify your task in [`skills/INDEX_BY_USE_CASE.md`](./skills/INDEX_BY_USE_CASE.md).
2. Read the relevant `skills/public/<name>/SKILL.md` files.
3. Copy any scaffold files from `skills/public/<name>/templates/` and substitute
   `{{placeholder}}` tokens.

### 3. Bootstrap a new project's context

Copy the `context/` folder into your new repository and fill in each template.
Run `bash context/validate-context.sh` to verify required sections are populated.

---

## Validation

```bash
# Validate all 40 skills (frontmatter, links, template references)
bash skills/validate-skills.sh

# Validate project context files (required sections are non-empty)
bash context/validate-context.sh

# Rebuild REGISTRY.md and BACKEND_GUILD.md from frontmatter
python3 skills/build-indexes.py
```

---

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). The short version:
- Keep skills **vendor-neutral** — no org-specific terms, registries, or libraries.
- Run `bash skills/validate-skills.sh` before submitting.
- Follow the authoring contract in [`skills/AUTHORING.md`](./skills/AUTHORING.md).

