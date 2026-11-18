---
name: git-commit-conventions
description: >
  Git commits that stay reviewable and bisectable — Conventional Commit prefixes, small single-purpose commits that
  each build, subject/body format, commit-msg hook, squash-vs-preserve policy. Use when creating a commit, splitting
  work into commits, or preparing a branch for review.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

# Git Commit Conventions Skill
## Purpose
Enforce consistent, readable, and meaningful git commit messages using industry-standard prefixes and best practices.

## When to Use
- **Only when the developer asks for a commit.** An agent never commits on its own (`completion-gate` §1); this skill
  tells you how to commit well *when asked*.
- Creating any git commit
- Reviewing pull requests for commit quality
- Splitting work into logical commits
- Preparing feature branches for merge

## Core Principles

### 1. Small, Focused Commits
- Each commit should represent one logical change
- Avoid bundling unrelated changes together
- Think "undo-able units" - what would you want to revert as a single operation?

### 2. Independent Compilation
- **Each commit must compile successfully on its own**
- Commit N can depend on commit N-1 (previous) ✅
- Commit N **cannot** depend on commit N+1 (future) ❌
- Build-time generated code: commit the generator input (e.g. the OpenAPI spec and plugin config) in the same
  commit as the code that uses the generated sources, so that commit still builds — no exception to the rule

### 3. Standard Prefixes
Use conventional commit prefixes from https://www.conventionalcommits.org/ and common practice:

| Prefix      | Usage                                                                 | Examples                                              |
|-------------|-----------------------------------------------------------------------|-------------------------------------------------------|
| `feat`      | New feature for the user                                              | `feat: add user authentication`                       |
| `fix`       | Bug fix                                                               | `fix: resolve crash in login handler on empty password`          |
| `docs`      | Documentation only changes                                            | `docs: update README with new installation steps`     |
| `style`     | Code formatting, whitespace, missing semi-colons (no logic change)    | `style: format CSS according to style guide`          |
| `refactor`  | Code change that neither fixes a bug nor adds a feature               | `refactor: extract validation logic to helper`        |
| `perf`      | Performance improvement                                               | `perf: optimize database query with index`            |
| `test`      | Adding or updating tests                                              | `test: add edge case tests for parser`                |
| `build`     | Changes to build system or external dependencies                      | `build: upgrade web framework to <version>`           |
| `ci`        | Changes to CI/CD configuration                                        | `ci: add SonarQube analysis to pipeline`              |
| `chore`     | Other changes that don't modify src or test files                     | `chore: remove unused dependencies`                   |
| `revert`    | Reverts a previous commit                                             | `revert: revert commit abc1234`                       |

### 4. Commit Message Structure

```
<type>[(<scope>)][!]: <short summary in imperative mood>

<optional detailed explanation>
- Why was this change needed?
- What alternatives were considered?
- Any side effects or implications?

<optional footers>
BREAKING CHANGE: <what breaks and how to migrate>   (only for breaking changes)
Co-authored-by: Name <email>
Fixes: #123
```

**Rules:**
- **Subject line**: ≤ 72 characters (hard limit), aim for ≤ 50; imperative mood ("add", not "added" or "adds")
- **Scope** (optional): the area changed, e.g. `feat(api): …`
- **Breaking change**: mark it with `!` after the type/scope, a `BREAKING CHANGE:` footer, or both (Conventional
  Commits accepts either; `release-versioning` bumps MAJOR for both). Use the footer to explain the migration
- **Body**: Wrap at 72 characters, explain WHY not WHAT (code shows what)
- **Blank line** between subject and body
- **No period** at end of subject line
- **Lowercase** after colon, unless the first word is an acronym (`feat: SSO login`), an identifier (`fix: UserService NPE`) or a product name (`build: Docker base image`); only a capitalised ordinary word (`feat: Add x`) is rejected

## Workflow

### Step 1: Plan Your Commits
Before coding, mentally outline the logical commit sequence:
```
1. feat: add domain model
2. feat: add repository layer
3. feat: add service layer
4. feat: add REST controller
5. test: add integration tests
6. docs: update API documentation
```
Each `feat` / `fix` commit carries its own unit tests, so every commit is tested and bisectable on its own;
a separate `test` commit is for tests added on top (integration tests, extra edge cases).

### Step 2: Stage Changes Incrementally
```bash
# Stage only files for commit 1
git add src/domain/user.<ext>

# Verify what's staged
git diff --cached

# Commit
git commit -m "feat: add user domain model"
```

### Step 3: Verify It Builds
Building the working tree proves nothing while other changes are still uncommitted — it builds files the commit
does not contain. Build the **committed snapshot** in a throw-away worktree (never `git stash` the developer's work):
```bash
# After EACH commit, verify the commit itself builds (and the fast tests pass)
git worktree add --detach ../verify-commit HEAD
(cd ../verify-commit && <build command>)
#   Java:                  mvn -q clean compile
#   Python:                uv run mypy && uv run pytest -x -m "not integration"
#   TypeScript / RN:       npm ci && npm run typecheck
git worktree remove --force ../verify-commit
```
For a whole branch the developer can run `git rebase -x '<build command>' <base>` (e.g. `-x 'mvn -q clean compile'`,
`-x 'npm run typecheck'`, `-x 'uv run mypy'`; developer-run: it rewrites history and the commit guard asks first).

If compilation fails, the commit is incomplete. Add the missing dependency or split differently.

### Step 4: Amend if Needed
Only when the developer asked for the amend, and never on a commit that is already pushed:
```bash
# Fix and amend the last commit (before pushing)
git add path/to/missing-file
git commit --amend --no-edit
```

## Examples

### ❌ Bad Commits
```
commit 1: "wip"
commit 2: "fix stuff"
commit 3: "added feature and fixed tests and updated docs"
commit 4: "revert"
commit 5: "Fixed the fix"
```
**Problems:**
- Meaningless messages ("wip", "fix stuff")
- Bundled unrelated changes (feature + tests + docs)
- Not self-explanatory
- No prefix

### ✅ Good Commits
```
commit 1: feat: add user registration endpoint

Add POST /api/v1/users endpoint with email validation.
Validates email format and checks for duplicates.
Unit tests cover happy path, duplicate email, and invalid email format.

commit 2: test: add integration tests for user registration

Exercise the endpoint against a real database.

commit 3: docs: update API documentation for user registration

Add request/response examples and error codes to OpenAPI spec.
```
**Why Good:**
- Clear, specific subject lines
- Each commit is independently understandable
- Logical sequence (feature with its unit tests → extra tests → docs)
- Uses standard prefixes

## Anti-Patterns to Avoid

### 1. "Junk Drawer" Commits
Bundling multiple unrelated changes:
```bash
❌ git commit -am "feat: add login + fix typo + update deps"
```
✅ Split into 3 commits:
```bash
git add src/auth/
git commit -m "feat: add login endpoint"

git add src/components/Header.tsx
git commit -m "fix: correct header typo"

git add package.json package-lock.json
git commit -m "build: upgrade react to <version>"
```

### 2. "Oops" Commits
Committing incomplete work that breaks the build:
```bash
❌ Commit adds UserService but doesn't add UserRepository it depends on
```
✅ Commit both together or commit in correct order:
```bash
git add src/repository/user_repository.<ext>
git commit -m "feat: add user repository"

git add src/service/user_service.<ext>
git commit -m "feat: add user service"

<build command>  # ✅ Compiles at each commit
```

### 3. Vague Messages
```bash
❌ "fix: fix bug"
❌ "refactor: improve code"
❌ "chore: updates"
```
✅ Be specific:
```bash
✅ "fix: prevent crash when user email is null"
✅ "refactor: extract duplicate validation logic to shared utility"
✅ "chore: remove deprecated config properties"
```

## Integration with Pull Requests

### Squash vs. Preserve Commits
- **Preserve commits** when each tells a story and could be cherry-picked individually
- **Squash** when commits are tiny WIP steps or fixes to earlier commits in the same PR

### PR Commit Checklist
Before requesting review:
- [ ] Each commit has a proper prefix
- [ ] Each commit message is clear and explains WHY
- [ ] Each commit compiles independently (developer-run: `git rebase -x '<build command>' <base>` — it rewrites history, so agents run it only when asked, and the commit guard asks before any rebase)
- [ ] Commits are in logical order
- [ ] No "fix typo" or "oops" commits (squash them with `git rebase -i` — developer-run, it needs an editor; agents never rewrite history unless asked)

## Tools

### Git Hooks
Add a commit-msg hook that enforces the prefix and the subject rules (≤ 72 characters, no trailing period, no capitalised ordinary word after the colon; acronyms, identifiers and listed product names pass). Keep it versioned in the repo (`scripts/commit-msg.sh`) and register it with
`pre-commit` rather than copying it into the unversioned `.git/hooks/`:
```yaml
# .pre-commit-config.yaml — then run once: pre-commit install --hook-type commit-msg
repos:
  - repo: local
    hooks:
      - id: conventional-commit-msg
        name: conventional commit message
        entry: scripts/commit-msg.sh
        language: script
        stages: [commit-msg]
```
```bash
#!/bin/sh
# scripts/commit-msg.sh (chmod +x) — receives the message file as $1

subject=$(tr -d '\r' < "$1" | sed -e '/^#/d' -e '/^[[:space:]]*$/d' | head -n 1)   # first non-comment line (as git does), CRLF-safe; subject only, not the body
# Merge commits, auto-generated reverts and the fixup!/squash!/amend! commits that `git rebase --autosquash` relies on are allowed through
case "$subject" in
    "Merge "*|"Revert \""*|"fixup! "*|"squash! "*|"amend! "*) exit 0 ;;
esac

prefix="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: ."
if ! echo "$subject" | grep -qE "$prefix"; then
    echo "ERROR: Commit message must start with a valid prefix, optional (scope), optional ! for breaking changes, then a summary:"
    echo "  feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert   e.g. feat(api)!: drop v1"
    echo "  (mark breaking changes with ! and/or a BREAKING CHANGE: footer — see release-versioning)"
    exit 1
fi
chars=$(printf '%s' "$subject" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')   # characters, not bytes, in any shell/locale
if [ "$chars" -gt 72 ]; then
    echo "ERROR: Subject line is $chars characters; the limit is 72."
    exit 1
fi
if echo "$subject" | grep -q '\.$'; then
    echo "ERROR: Subject line must not end with a period."
    exit 1
fi
first=$(printf '%s' "$subject" | sed -E 's/^[^:]*: //; s/ .*//')
if printf '%s' "$first" | grep -qE '^[A-Z][a-z]+$' &&
   ! printf '%s' "$first" | grep -qxE 'Docker|Redis|Kafka|Spring|Java|Python|Kotlin|Swift|GitHub|GitLab|Maven|Gradle|Kubernetes|Helm|Jenkins|Postgres|Flyway|Jackson|Lombok|Sonar|Mockito|React|Node|Jira|Bitbucket|Oracle|Prometheus|Grafana|Hibernate|Jakarta|Android|Expo|Metro'; then
    echo "ERROR: Start the summary with a lowercase verb after the colon (feat: add x, not feat: Add x)."
    echo "  Acronyms (SSO, JWT), identifiers (UserService) and listed product names (Redis) are fine; extend the list in scripts/commit-msg.sh."
    exit 1
fi
```

### Interactive Rebase
Clean up commits before pushing. **Developer-run** — it needs an interactive editor and rewrites history, so an
agent does not run it; an agent may suggest the plan (which commits to squash / reword) and the developer runs it:
```bash
git rebase -i HEAD~5

# In the editor:
pick abc1234 feat: add user model
squash def5678 fix: typo in user model  # Merge into previous
pick ghi9012 test: add user tests
reword jkl3456 feat: add login  # Edit message
```

## Decision Tree

```
Is this change...

├─ A new capability? → feat
├─ Fixing broken behavior? → fix
├─ Improving performance? → perf
├─ Restructuring without changing behavior? → refactor
├─ Only adding/updating tests? → test
├─ Only changing docs? → docs
├─ Only changing formatting? → style
├─ Changing build/deps? → build
├─ Changing CI/CD? → ci
└─ None of the above (cleanup, config, etc.)? → chore
```

## Skill Checklist

When creating commits, verify:
- [ ] Used standard prefix from the table above
- [ ] Subject line is ≤ 72 characters (aim ≤ 50), imperative mood, lowercase after colon
- [ ] Each commit is focused on one logical change
- [ ] Each commit compiles independently
- [ ] Commit message explains WHY, not just WHAT
- [ ] No "wip", "fix", or other vague messages
- [ ] Commits are in dependency order (later commits can depend on earlier ones)

## Cross-references
- [`release-versioning`](../release-versioning/SKILL.md) — consumes these prefixes to drive SemVer bumps, CHANGELOG generation, and `commitlint` enforcement.
- The language's CI skill runs the same commitlint check in the pipeline — Java: the Jenkins `ci` PR-only `Commit messages` stage or `github-actions-ci`'s `lint-commits.yml`; Python / React Native: add `lint-commits.yml` from `release-versioning` §1 next to the `python-ci` / `react-native-ci` workflows. Make it a required check only once that job exists.
- Pull-request review — commit hygiene is part of it: apply the PR Commit Checklist above alongside the language's review (Java `quality-review`; the `python-code-review` / `react-native-code-review` agents), which reviews the code, not the commits.

## References
- [Conventional Commits](https://www.conventionalcommits.org/)
- [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/)
- [Common Git Message Prefixes](https://jabaltorres.com/blog/common-git-message-prefixes/)

## Examples from Practice

See your own repository history for examples of well-structured commits following these conventions.

Good examples follow the pattern:
```
<prefix>: <imperative summary>

<optional body explaining context and rationale>

<optional footers>
```
