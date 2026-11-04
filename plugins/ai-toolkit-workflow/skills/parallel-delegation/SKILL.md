---
name: parallel-delegation
description: >
  When and how to hand work to subagents in parallel without conflicts — what is safe to delegate, how to brief a
  subagent, file ownership, verifying results. Use when a task spans two or more independent units or before
  dispatching any subagent; skip for small single-file changes.
tier: should
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Parallel Delegation Skill
Subagents start with an empty context, so a delegation is only as good as its brief.
Delegation pays off when units are independent; it costs more than it saves when they are not.

## 1. When to delegate

Delegate when **all** hold:

- two or more units of work, each finishable without the others' output;
- the units touch **disjoint files** (see §3);
- each unit has a checkable result (tests pass, file exists, report returned).

Do the work yourself when it is a handful of edits, a strict dependency chain
(migration → entity → repository → service → controller), or it needs decisions the
developer has not confirmed yet.

## 2. What to delegate, what to keep

| Delegate (parallel) | Keep in the main thread (sequential) |
| --- | --- |
| Unit tests per class group → the language's test-writer agent | Design and developer confirmation |
| Component / integration tests → the language's test-writer agent | Shared contracts: DTOs, error types and catalogue |
| Docs + CHANGELOG → `ai-toolkit-docs:update-context` | Anything that edits a file another unit also edits |
| Independent layers (client, validator, metrics recorder) → `general-purpose` | Running the full build and static analysis |
| Final audit, after all edits land → the language's code-review agent (read-only) | Merging results and the final answer |

Typical shape: **sequential core → parallel fan-out → sequential audit**.
Generate the shared core yourself, dispatch the independent units in one message, then run
the language's code-review agent once everything has landed.

## 3. File ownership

- Give every subagent an explicit list of files it may create or edit. No file belongs to two subagents.
- Shared files (build manifest such as `pom.xml`/`pyproject.toml`/`package.json`, config, the error catalogue, the API contract) are edited only
  by the main thread — before the fan-out, or after it from the subagents' reported requests.
- Never run two subagents that both build or test the project in the same working tree.
  Subagents write code; the main thread runs the build.
- For risky or large parallel edits use `isolation: "worktree"`.

## 4. The brief

A subagent knows nothing you do not write down. Every brief contains:

```
Goal:        one sentence — the observable end state
Context:     what already exists (paths, class names, signatures it must call)
Skills:      load <skill-a>, <skill-b> before writing code
Files:       may create/edit: <list>; must not touch anything else
Constraints: non-negotiables that apply, naming, package, test naming
Done when:   concrete check (e.g. one test file passes: `mvn -q test -Dtest=FooTest` / `pytest tests/test_foo.py` / `jest foo.test.ts` — report; do not run it if the main thread owns builds)
Return:      files changed + 3-line summary + anything you could not do
```

Brief it like a peer: state what is already ruled out, and do not hand over your conclusion
as a question — hand over the task.

## 5. Dispatch

- Send all independent subagents in **one message** so they run concurrently. Keep it to ~4.
- Use the narrowest agent and call it by its **qualified name** (bare names do not resolve for the Agent tool):
  tests → `ai-toolkit-java-agents:test-writer`, `ai-toolkit-python-agents:python-test-writer` or
  `ai-toolkit-react-native-agents:react-native-test-writer`; docs → `ai-toolkit-docs:update-context`; audits → the
  language's code-review agent (`ai-toolkit-java-agents:code-review`, `ai-toolkit-python-agents:python-code-review`,
  `ai-toolkit-react-native-agents:react-native-code-review` — not the built-in `/code-review` skill);
  `general-purpose` only for generation that has no dedicated agent.
- Tell every test-writer in its brief: **do not run builds or tests — the main thread owns builds** (concurrent runs
  corrupt shared build output and coverage files).
- Subagents cannot spawn subagents. If *you* are a subagent, the Agent tool is not
  available — do the same steps inline, in order.

## 6. Verify what comes back

A subagent's summary describes what it intended, not necessarily what it did.

1. Read the diff of every file it reports changing; check nothing outside its file list changed.
2. Run the build and tests yourself.
3. Run the language's code-review agent (or apply the language's standards (Java: `quality-review` + `golden-path`; Python / React Native: the Do/Don't lists of the loaded `python-*` / `react-native-*` skills)) on the combined diff — a clean unit does not make a clean whole.
4. If a result is wrong, fix it directly or re-brief with the specific failure; do not re-send the same brief.

## Anti-patterns

- ❌ Delegating a three-line change — the brief costs more than the edit.
- ❌ Two subagents editing the same file or the same package's `package-info`/config.
- ❌ Fan-out before the shared contract (DTOs, exceptions, interfaces) exists.
- ❌ Trusting "all tests pass" from a subagent without running them.
- ❌ Asking a subagent to make a design decision the developer has not approved.
- ✅ Sequential core, parallel leaves, one audit at the end.

## Cross-references

- `unit-tests`, `component-tests` and their Python / React Native counterparts — what the test-writer agents apply.
- `quality-review` and `golden-path` (Java), the `python-*` / `react-native-*` skills (their Do/Don't lists) — what the language's code-review agent applies to the combined diff.
- `context-maintenance` — what `ai-toolkit-docs:update-context` applies.
