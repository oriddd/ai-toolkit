# Skills

A complete, vendor-neutral set of agent skills for building Java 21 /
Spring Boot microservices.

```
skills/
└── public/   ← all skills live here
```

## What you get

A complete recipe for a production-grade microservice — from the first
commit to a running Kubernetes pod — using only public Spring Boot,
Maven, Jenkins or GitHub Actions, and Helm primitives. No private
libraries or organization-specific infrastructure is assumed.

## Usage

Start from the **[`public/project-types`](./public/project-types/SKILL.md)**
meta-skill. It maps your project shape (sync REST, event-driven,
scheduler, library, or monolith-with-bones) to the right combination of
skills and calls the HITL scaffolder.

Or go directly to **[`public/create-repo`](./public/create-repo/SKILL.md)**
if you already know what you need.

For the curated **MUST / SHOULD / MAY** bundle that backend teams are
expected to follow, see **[`BACKEND_GUILD.md`](./BACKEND_GUILD.md)** —
that document is what code-generating agents drive from in this repo.

## Maintainer references

| Resource | Purpose |
| --- | --- |
| [`BACKEND_GUILD.md`](./BACKEND_GUILD.md) | Curated MUST / SHOULD / MAY adoption matrix + apply-order + task-driven recipes + non-negotiables for code review. |
| [`REGISTRY.md`](./REGISTRY.md) | Machine-readable index of every skill (counts, templates indicator). |
| [`AUTHORING.md`](./AUTHORING.md) | SKILL.md authoring contract — frontmatter rules, required sections, placeholder syntax, checklist. |
| [`validate-skills.sh`](./validate-skills.sh) | CI-friendly linter — fails on missing frontmatter, mismatched folder/`name`, broken template links, missing registry entries. |

Run the validator before opening a PR that touches `skills/`:

```sh
bash skills/validate-skills.sh
```

## Optional publication-safety check

If you maintain a private fork that adds organization-specific terms
you do not want leaking into shared skill files, create a
`skills/.publication-blocklist` file (one substring per line, `#` for
comments). The validator's §6 check fails the build if any blocklisted
term appears in any `*.md` under `skills/`. The shipped catalogue
contains no such file and the check is a no-op by default.
