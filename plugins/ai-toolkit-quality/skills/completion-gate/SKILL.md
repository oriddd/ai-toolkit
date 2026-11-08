---
name: completion-gate
description: >
  Definition of done — never commit until asked; before saying done, prove build, full tests, static analysis,
  language standards, meaningful coverage, hygiene and Sonar with evidence. Use when finishing any code change, before
  reporting it done, and after every fix made during the check.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [code-hygiene, sonar-quality-gate]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Completion Gate Skill
## When to use

Use at the end of every implementation task, before telling the developer it is done, and again
after each fix the gate makes you do. It decides "done"; the language skills define the details.

## 1. Commit policy — never commit until asked

- Do **not** run `git commit`, `git commit --amend`, `git push`, `git tag` or open a PR unless the
  developer explicitly asks for it in this conversation. Finishing a task is not a request to commit.
- Leave the changes in the working tree. When the gate is green, say so and offer to commit.
- When asked, follow `git-commit-conventions` and commit only the files that belong to the task.
- Do **not** run `git stash`, `git stash pop`, `git checkout -- <file>`, `git restore` or `git clean` mid-task to get a
  clean tree (for a baseline build, for example). It hides or discards the developer's uncommitted work and a failed
  `pop` leaves conflicts. To compare against the base branch, use a separate worktree (`git worktree add`) or ask.
- `ai-toolkit-workflow` ships a best-effort hook that asks for confirmation before direct `git commit|push|tag|rebase|merge|
  cherry-pick|am|revert`, `gh pr create|merge`, `npm version|publish` and `mvn release:*|deploy` in Claude's Bash tool.
  It cannot see aliases, scripts that commit internally, or other tools — it is a backstop, not a guarantee, and a prompt
  does not replace the developer's request. The rule is yours to follow.

## 2. The gate

Run in order. On a failure fix the root cause, then restart from the build (a fix can break what already passed).

| # | Check | Passes when |
| --- | --- | --- |
| 1 | **Scope** | `git status` / `git diff --stat` show only files that belong to the task — no debug output, generated noise, formatting churn or stray files. |
| 2 | **Build** | A clean build of the whole project succeeds. |
| 3 | **Tests** | The **full** suite passes, not only the new tests. |
| 4 | **Static analysis** | The language's lint, format and type/analysis checks pass (`static-analysis` skill of the language). |
| 5 | **Standards** | The diff satisfies the language standards: run the language's code-review **agent** through the Agent tool when it is available — `ai-toolkit-java-agents:code-review`, `ai-toolkit-python-agents:python-code-review` or `ai-toolkit-react-native-agents:react-native-code-review` (not the built-in `/code-review` skill) — or apply the language's standards (Java: `quality-review` + `golden-path`; Python / React Native: the Do/Don't lists of the loaded `python-*` / `react-native-*` skills) yourself. |
| 6 | **Coverage** | Every new or changed behaviour and branch has a test that would fail if it broke; coverage of the changed code is reported with each uncovered line explained. |
| 7 | **Hygiene** | `code-hygiene` is clean: no needless comments/docs, dead code, speculative abstraction, or redundant tests. |
| 8 | **Sonar** | `sonar-quality-gate` passes on new code, or is reported **not verified** with the reason. Read the CI result; run an analysis yourself only after the developer confirms (it writes to a shared server). |
| 9 | **Docs** | Project docs and context files are updated when the change warrants (`context-maintenance`). `CHANGELOG.md` is edited by hand only when no release bot owns it (`release-versioning`). |

## 3. Commands by language

Prefer the project's own wrapper (`make verify`, `npm run verify`) when it exists.

| Language | Build + tests + analysis | Coverage of changed code |
| --- | --- | --- |
| Java / Maven | `mvn -B clean verify` (Spotless, Checkstyle, SpotBugs, ArchUnit, JaCoCo run in the build) and the project's PIT mutation run, e.g. `mvn org.pitest:pitest-maven:mutationCoverage` (non-negotiable 12, score ≥ 75 %) | `diff-cover target/site/jacoco/jacoco.xml --compare-branch=origin/<default-branch> --src-roots src/main/java`; Sonar new-code coverage |
| Python | the verify sequence from `python-static-analysis` §5: `uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run lint-imports && uv run pytest -m "not integration"` (+ `uv run pytest -m integration` when Docker is available) | `uv run pytest -m "not integration" --cov --cov-report=xml` + `diff-cover coverage.xml --compare-branch=origin/<default-branch>` |
| React Native | `npm run verify` (`tsc --noEmit`, `eslint . --max-warnings 0`, `prettier --check .`, `jest --ci --coverage` — see `react-native-static-analysis`) | `jest --coverage` + changed files from `git diff` |

If a command does not exist for the project, say so — do not invent a substitute and call it passing.

**Blocked by the environment.** When Docker (Testcontainers integration tests) or the PIT run cannot run here —
no Docker daemon, no network, sandbox limits — do not report the build as passing:

- Run what can run and skip only the blocked part explicitly: `-DskipITs` for Failsafe integration tests, `-DskipPitest`
  for PIT (`-Dpit.skip` is not a PIT property and does nothing), `-m "not integration"` for pytest.
- Report each skipped check as **not verified — blocked by the environment (<reason>)**, never as pass.
- Compare with the baseline where you can: say whether the same check was already blocked or failing before the
  change, so the developer knows what is left to verify in CI.

## 4. Evidence, not assertions

Finish with a table. A row is **pass** only when you saw the command succeed in this session.

```
| Check          | Command                  | Result                         |
| Build          | mvn -B clean verify      | pass (BUILD SUCCESS, 412 tests)|
| Static analysis| (part of verify)         | pass                           |
| Coverage       | jacoco + diff            | pass — 2 uncovered lines: <why>|
| Sonar          | sonar-maven-plugin:sonar | not verified — no SONAR_TOKEN  |
```

Results are `pass`, `fail` or `not run/not verified` with the reason. Never write "should pass", and never
turn a skipped check into a pass.

## 5. When a check fails

- Fix the cause in the code. Do **not** make it green by suppressing it: no `@SuppressWarnings`, `# noqa`,
  `eslint-disable`, `@Disabled`/`skip`, deleting or weakening tests, excluding files from coverage or Sonar,
  or lowering thresholds — unless the developer approves that specific suppression, with a stated reason.
- The exclusions the standards themselves prescribe are not suppressions: generated sources are excluded from coverage,
  formatting and static analysis by design (Java non-negotiable 14, `openapi-first-codegen`).
- A flaky or pre-existing failure is reported, not hidden: say which check, which test, and that it predates the change.
- If you cannot make it pass, stop and report what is failing and why instead of declaring done.

## 6. Delegation

Checks 5–7 are independent reads of the same diff: when subagents are available run them in parallel
(`parallel-delegation`) — the code-review agent is read-only. The build and test runs stay in the main thread
(one build per working tree), and check 8 (Sonar) runs **after** 5–7 because it builds the project itself.

**Run the gate once.** When you are a subagent (for example a builder agent), run the gate yourself and return the
§4 evidence table with your result. The calling session relays that table verbatim and does not re-run the gate
unless the code changed after the table was produced — then it re-runs from the build. If the Agent tool is not
available to you, apply the check 5 standards inline and say so in the table.

## Anti-patterns

- ❌ Committing "to save progress" or because the task finished.
- ❌ Reporting done after running only the new tests.
- ❌ Calling Sonar green without having reached the server.
- ❌ Green by suppression, exclusion or a lowered threshold.
- ❌ Padding tests to reach a coverage number.
- ❌ `git stash` / `stash pop` mid-task to get a clean tree — use a separate worktree.
- ❌ Reporting a check blocked by the environment (Docker, PIT) as pass.
- ✅ Fix, re-run from the build, report with evidence, then ask whether to commit.

## Cross-references

`code-hygiene`, `sonar-quality-gate`, `parallel-delegation`, `context-maintenance`, `git-commit-conventions` (when asked to
commit), and per language its static-analysis, unit-test and review skills (Java `static-analysis`, `unit-tests`, `quality-review`, `golden-path`; `python-static-analysis`, `python-unit-tests`; `react-native-static-analysis`, `react-native-unit-tests`).
