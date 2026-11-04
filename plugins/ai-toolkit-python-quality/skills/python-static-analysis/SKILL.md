---
name: python-static-analysis
description: Mechanically enforce style and catch bug classes in Python — ruff (lint + format), mypy --strict, pre-commit hooks and one pyproject.toml configuration, all wired so any violation breaks the build and cannot be skipped. Use when a repo is created, a tool is configured or a lint/type error needs resolving. Not for test design (use `python-unit-tests`) or pipeline wiring beyond the commands themselves (use `python-ci`).
tier: must
applies_to: [rest, worker, cli, library]
depends_on: [python-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python Static Analysis Skill
## When to use
When creating a repo, configuring tooling, or whenever `ruff` / `mypy` reports a problem.

## Layout

```
pyproject.toml              # single source of tool configuration
.pre-commit-config.yaml     # same checks, local gate
.github/workflows/ci.yml    # same checks, authoritative gate (see `python-ci`)
```

## Dependencies
```toml
[dependency-groups]
dev = ["ruff>=0.6", "mypy>=1.11", "pre-commit>=3.8", "import-linter>=2.0"]
```

## 1. Ruff: lint and format in one tool
```toml
[tool.ruff]
line-length = 100
target-version = "py312"
src = ["src", "tests"]

[tool.ruff.lint]
select = [
  "E", "F", "W", "I",   # pycodestyle, pyflakes, import order
  "B", "BLE",           # bugbear, blind except
  "UP", "SIM", "C4",    # modern syntax, simplifications
  "ASYNC", "S",         # async misuse, security (bandit)
  "PL", "RET", "TID",   # pylint subset, returns, banned imports
  "ANN", "T20", "DTZ",  # annotations, no print, naive datetimes
  "N",                  # pep8-naming (makes the N802 test ignore below meaningful)
  "PGH", "RUF",         # blanket type-ignore/noqa bans; RUF100 = unused (stale) noqa
]
ignore = ["PLR0913"]    # decide per project; keep the ignore list short and commented

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "ANN", "PLR2004", "N802"]
```

`ruff format` is the only formatter; no black/isort alongside it.

## 2. mypy strict
```toml
[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["pydantic.mypy"]
warn_unreachable = true
files = ["src", "tests"]
```
Every function is fully typed; `Any` is a last resort. Prefer `Protocol`, `TypedDict`, generics.
Third-party packages without stubs get a narrow `[[tool.mypy.overrides]]` for that module, not a global ignore.

## 3. Architecture rules
Enforce the dependency direction from `python-code-structure` with import-linter:

```toml
[tool.importlinter]
root_package = "my_service"
include_external_packages = true          # required as soon as a contract forbids a third-party package (fastapi)

[[tool.importlinter.contracts]]
name = "services do not import the api layer or fastapi"
type = "forbidden"
source_modules = ["my_service.services"]
forbidden_modules = ["my_service.api", "fastapi"]
```
Every module named in a contract must exist or `lint-imports` fails with "Module ... does not exist":
add `my_service.operations` to `source_modules` only once that package is created (see `python-code-structure`:
create only the packages you need).

## 4. Pre-commit
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format
  - repo: local
    hooks:
      - id: mypy
        name: mypy --strict
        entry: uv run mypy
        language: system
        pass_filenames: false
      - id: import-linter
        name: import-linter
        entry: uv run lint-imports
        language: system
        pass_filenames: false
```
Install once with `uv run pre-commit install`. Hooks are a convenience; CI is the gate.

## 5. Non-skippable: the verify sequence
The same commands run locally, in pre-commit and in CI, and fail the build. This is **the verify
sequence** (canonical definition in `python-ci`):

```
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run lint-imports && uv run pytest -m "not integration"
```
plus `uv run pytest -m integration` when Docker is available. `--no-verify` and ignoring CI do not make
code mergeable.

## 6. Suppressions
A suppression is a documented exception, never a fix: `# noqa: S603 - args are constants` /
`# type: ignore[assignment]  # stub bug, see TICKET-123`. Always the specific code plus a reason.
Stale suppressions fail the build: ruff `RUF100` flags an unused `# noqa`, mypy `warn_unused_ignores`
(part of strict) flags an unused `# type: ignore`. `PGH003` / `PGH004` only ban the *blanket* forms
(`# type: ignore`, `# noqa` without a code).

## Do / Don't
- ✅ Fix the root cause; add types rather than ignores.
- ✅ Keep all configuration in `pyproject.toml`.
- ✅ Ratchet: when enabling a new rule, fix or explicitly baseline per-file, never turn it off globally.
- ❌ Blanket `# noqa` / `# type: ignore`, or `ignore_errors = true` for a package.
- ❌ Excluding `src/` directories from checks to make CI green.
- ❌ Running a second formatter, or tools pinned differently locally and in CI.

## Cross-references
- `python-ci` — runs these gates on every pull request.
- `python-code-structure` — the layering these rules protect.
- `python-unit-tests` — tests are linted and typed too.
