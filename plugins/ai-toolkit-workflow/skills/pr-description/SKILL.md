---
name: pr-description
description: >
  Pull request descriptions — problem, solution, key changes, testing, notes; update the PR on any git host (GitHub,
  GitLab, Azure DevOps, Bitbucket) without clobbering concurrent edits. Use when creating a PR, updating its
  description, or summarising a branch for reviewers.
tier: should
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [git-commit-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# PR Description Skill
## When to Use
- Opening a pull request and writing its initial description
- Updating an existing PR description after design changes or reviewer feedback
- Summarising what a branch does so someone unfamiliar with the work can review it
- After completing a feature, before requesting review

## 1. Description Structure

A good PR description answers, in four required sections plus optional Notes, what a reviewer asks before reading a single line of code:

```
## Problem
One or two sentences. What was broken, missing, or needed? Why does this change exist?

## Solution
How was the problem solved? High-level — save detail for the "Key Changes" section.

## Key Changes
Bullet list, one item per logical change. Each item names the file / component and explains
what it does differently now. Group related items. Aim for 5–12 bullets.

## Testing
How was this verified? Unit tests, integration tests, manual steps, mocked dependencies.
Mention test class names or scenarios if noteworthy.

## Notes  *(optional)*
Breaking changes, follow-up tickets, known limitations, deployment steps, config changes.
```

**Rules:**
- Write in present tense ("adds", "removes", "replaces") — the description says what the PR does; commit subjects stay in the imperative (`git-commit-conventions`)
- Describe *why*, not just *what* — the diff already shows what
- Keep each bullet to one line; expand in "Notes" only if truly necessary
- Avoid internal jargon or ticket IDs as the sole explanation; always include a human summary
- If a state machine, data flow, or non-obvious algorithm is involved, include a short ASCII/Mermaid diagram or numbered flow

---

## 2. Updating a PR Description

> **Ask first.** Show the developer the proposed description and write it to the PR only after they approve — this is an
> external write. The commit guard asks before `gh pr create` / `gh pr edit` and `gh api` writes, but not before `glab`,
> `az` or `curl` calls, so the rule is yours to follow. If they decline, hand them `description.md` to paste.

Detect the host from `git remote get-url origin`, then use its CLI (authenticated by the developer) or REST API:

| Host | Update an existing PR | Notes |
| --- | --- | --- |
| GitHub | `gh pr edit <n> --body-file description.md` | `gh pr create --body-file description.md` when the developer asked you to open it |
| GitLab | `glab mr update <n> --description "$(cat description.md)"` | |
| Azure DevOps | `az repos pr update --id <n> --description "$(cat description.md)"` | 4,000-character limit |
| Bitbucket Cloud | `PUT https://api.bitbucket.org/2.0/repositories/{workspace}/{repo}/pullrequests/{id}` with `title` and `description` | token from the environment |
| Bitbucket Server / Data Center | REST API with optimistic locking — follow [`references/bitbucket-server.md`](./references/bitbucket-server.md) | must send `version`, `title`, `reviewers` |
| Anything else | its CLI or REST API, same rules | |

Rules on every host:
- Read the token from the environment and keep it off the command line (feed headers to `curl -K -` on stdin).
- Fetch the PR first and send back every field you do not mean to change; on a concurrent-edit conflict, re-fetch and
  retry — never overwrite someone else's edit blindly.
- Build JSON bodies with `jq --rawfile`, never by hand-escaping quotes and newlines.

---

## 3. Composing the Description from Branch Changes

When asked to update a PR description:

1. **Identify the diff scope** — `git fetch origin <default-branch>` first (a stale ref gives the wrong commit list), then `git log --oneline origin/<default-branch>..HEAD` to list commits; `git diff origin/<default-branch>...HEAD --stat` to list changed files (`main`, `master` — whatever the repo uses).
2. **Group changes by concern** — config, domain model, client layer, service logic, tests, docs.
3. **Write the Problem section first** — derive it from the ticket, commit messages, or the user's words; never leave it vague.
4. **Write Key Changes as bullet items** — one item per changed component, explaining the *effect* of the change, not just the file name.
5. **Include state machine / flow diagrams** where logic is non-trivial (ASCII or Mermaid).
6. **Summarise test coverage** — list tests or scenarios added; note mocked dependencies if relevant.
7. **Check the Notes section** — mention any config flag changes, new environment variables, schema changes, or follow-up work.

---

## 4. Examples

### ✅ Good Key Changes bullet
```
- `OrderSyncOrchestrator` — new shared sync engine; replaces two divergent
  implementations; driven by `SyncMode` (BATCH for scheduled runs, ON_DEMAND for reads)
```

### ❌ Bad Key Changes bullet
```
- Updated OrderSyncOrchestrator
```

### ✅ Good Problem section
```
Order statuses stored in the database drifted from the live state in the upstream system because the
scheduled batch job and the on-demand read-time sync followed different code paths with
separate mapping tables and no shared state machine.
```

### ❌ Bad Problem section
```
See PROJ-1234
```

---

## 5. Checklist

Before calling the PR "described":

- [ ] Problem section answers *why* the change exists (not just a ticket ID)
- [ ] Solution section explains the approach at a glance
- [ ] Every changed component has a bullet in Key Changes
- [ ] Bullets say what the component *does differently*, not just what file changed
- [ ] Testing section names at least the test class(es) added or the manual steps taken
- [ ] Any state machine, non-trivial algorithm, or data flow has a diagram or numbered walkthrough
- [ ] Notes lists any breaking changes, config changes, or follow-up work
- [ ] After the developer approved, the description was written to the PR (fields you did not change sent back unchanged, no conflict) — or handed to the developer to paste

---

## Anti-Patterns

| ❌ Don't | ✅ Do instead |
|---|---|
| Write only a ticket ID as the description | Always add a human summary alongside the ticket reference |
| Send a partial update body the host treats as a full replace | Copy the current `title` (and `reviewers`, where the API needs them) into the payload |
| Overwrite a concurrent edit | Fetch the current PR first; use its version / ETag where the host supports it |
| Write what changed (the diff) | Write *why* it changed and what the effect is |
| Leave the description blank until "later" | Write a draft description before requesting the first review |
| Describe every file individually | Group by logical concern; omit trivial files (test helpers, imports) |

---

## Cross-references
- [`git-commit-conventions`](../git-commit-conventions/SKILL.md) — commit messages are the raw material; a good PR description synthesises them into a coherent narrative.
- `documentation-and-adr` — for architectural decisions that deserve a longer-lived record beyond the PR description.
