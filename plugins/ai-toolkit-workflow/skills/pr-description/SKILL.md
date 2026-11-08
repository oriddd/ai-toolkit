---
name: pr-description
description: >
  Pull request descriptions on Bitbucket Server — problem, solution, key changes, testing, notes; fetch and update the
  PR atomically via the REST API with optimistic locking. Use when creating a PR, updating its description, or
  summarising a branch for reviewers.
tier: should
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [git-commit-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-08-12
---

# PR Description Skill
## When to Use
- Opening a pull request and writing its initial description
- Updating an existing PR description after design changes or reviewer feedback
- Summarising what a branch does so someone unfamiliar with the work can review it
- After completing a feature, before requesting review

## 1. Description Structure

A good PR description answers four questions a reviewer will ask before reading a single line of code:

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

## 2. Updating a PR Description via Bitbucket REST API

> **Ask first.** Show the developer the proposed description and write it to the PR only after they approve — this is an
> external write that the commit guard does not intercept. Keep the token out of the process list: the helper below
> feeds the header to curl on stdin. These recipes are for Bitbucket Server; for GitHub use `gh pr edit <n> --body-file
> description.md` (same rule: ask first).

```bash
# Reads the token from the environment; never put it on a command line
bb() { printf 'header = "Authorization: Bearer %s"\n' "$BITBUCKET_TOKEN" | curl -s -K - "$@"; }
```

### Step 1 — Fetch the current PR (captures `version` for optimistic locking)

```bash
bb "https://<host>/rest/api/1.0/projects/{proj}/repos/{repo}/pull-requests/{id}" \
  | jq '{id, title, description, version}'
```

Note the `version` integer — it is required for the update call.

### Step 2 — Replace the description

Write the new description to a file and let `jq` build the JSON — hand-escaping quotes and newlines breaks on real text:

```bash
body="$(mktemp)"
jq -n --argjson version <VERSION> \
      --arg title "<current title — must be included even if unchanged>" \
      --rawfile description description.md \
      '{version: $version, title: $title, description: $description}' > "$body"
bb -X PUT \
  -H "Content-Type: application/json" \
  --data @"$body" \
  "https://<host>/rest/api/1.0/projects/{proj}/repos/{repo}/pull-requests/{id}"
rm -f "$body"
```

**Important:**
- `version` must match the current version or the server returns `409 Conflict`
- `title` must always be included in the PUT body (it resets to empty if omitted)
- The description must be a valid JSON string — let `jq --rawfile` (Step 2) escape newlines and quotes; never hand-escape
- On `409`, re-fetch the PR to get the latest `version` and retry

### Parsing a PR URL

Given `https://<host>/projects/PROJ/repos/my-service/pull-requests/42`:

| Segment   | Value       | Position in URL              |
|-----------|-------------|------------------------------|
| `project` | `PROJ`      | `/projects/{project}/`       |
| `repo`    | `my-service`| `/repos/{repo}/`             |
| `PR_ID`   | `42`        | `/pull-requests/{PR_ID}`     |

---

## 3. Composing the Description from Branch Changes

When asked to update a PR description:

1. **Identify the diff scope** — `git log --oneline origin/<default-branch>..HEAD` to list commits; `git diff origin/<default-branch>...HEAD --stat` to list changed files (`main`, `master` — whatever the repo uses).
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
- [ ] Description was written to the PR via the REST API with the correct `version` (no `409`)

---

## Anti-Patterns

| ❌ Don't | ✅ Do instead |
|---|---|
| Write only a ticket ID as the description | Always add a human summary alongside the ticket reference |
| Forget to include `title` in the PUT body | Always copy the current `title` into the update payload |
| Skip optimistic locking (`version`) | Fetch the current PR first; use its `version` in the PUT |
| Write what changed (the diff) | Write *why* it changed and what the effect is |
| Leave the description blank until "later" | Write a draft description before requesting the first review |
| Describe every file individually | Group by logical concern; omit trivial files (test helpers, imports) |

---

## Cross-references
- [`git-commit-conventions`](../git-commit-conventions/SKILL.md) — commit messages are the raw material; a good PR description synthesises them into a coherent narrative.
- `documentation-and-adr` — for architectural decisions that deserve a longer-lived record beyond the PR description.
