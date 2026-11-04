---
name: python-ci
description: >
  Python 3.12 CI — GitHub Actions with uv and caching, separate lint, type, unit and integration gates, plus a
  multi-stage, non-root Dockerfile. Use when bootstrapping a repo or moving a service onto the standard pipeline. Lint
  rules live in `python-static-analysis`.
tier: must
applies_to: [rest, worker, cli, library]
depends_on: [python-static-analysis, python-unit-tests]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python CI Skill
## When to use
When bootstrapping a Python repository, or when the pipeline or container image needs to follow the standard.

## Layout

```
.github/workflows/ci.yml
Dockerfile
.dockerignore
pyproject.toml + uv.lock        # lock file is committed; CI installs with --locked (fails on drift)
```

## 1. The verify sequence
One sequence, identical locally and in CI. It is what "verified" means in this toolkit and what the
`completion-gate` skill runs for Python:

```
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run lint-imports && uv run pytest -m "not integration"
```
plus `uv run pytest -m integration` when Docker is available (pytest exits 5 when no integration test exists; the CI job accepts exactly that code with `|| [ $? -eq 5 ]`, any other failure still fails). The CI jobs below are this sequence split
into separately named jobs; the unit job adds `--cov` so the `fail_under` threshold applies.

## 2. Workflow
Gates run as separate jobs so a failure names its cause; all are required checks on the default branch.

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]        # replace `main` with the repository's default branch name
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
        with:
          version: "0.4.30"      # same uv as the Dockerfile image tag
          enable-cache: true
          cache-dependency-glob: uv.lock
      - run: uv sync --locked
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy
      - run: uv run lint-imports

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
        with: { version: "0.4.30", enable-cache: true, cache-dependency-glob: uv.lock }
      - run: uv sync --locked
      - run: uv run pytest -m "not integration" --cov   # fail_under lives in [tool.coverage.report]

  integration:
    runs-on: ubuntu-latest          # Docker available for testcontainers
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
        with: { version: "0.4.30", enable-cache: true, cache-dependency-glob: uv.lock }
      - run: uv sync --locked
      - run: uv run pytest -m integration || [ $? -eq 5 ]   # exit 5 = no integration test collected yet

  image:
    needs: [quality, unit, integration]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: my-service:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

`uv sync --locked` fails when `uv.lock` no longer matches `pyproject.toml`; `--frozen` installs the
lock as-is and never notices drift, so it is not a CI check.

Optional Sonar stage (only if the organisation runs Sonar): produce the coverage report in the unit
job with `uv run pytest -m "not integration" --cov --cov-report=xml`, then scan with
`sonar.python.coverage.reportPaths=coverage.xml` in `sonar-project.properties`
(set `relative_files = true` under `[tool.coverage.run]` if the scan runs in another checkout path).
Pass the token only through the `SONAR_TOKEN` environment variable (from a CI secret); never as
`-Dsonar.token=...` on the command line, where it leaks into logs and process lists.

Pin actions to a major version at minimum (a SHA for third-party ones). Matrix over Python versions
only for libraries; services test the one version they ship. Push the image only from the default branch, in a
separate step with registry credentials scoped to that job.

## 3. Dockerfile: multi-stage, non-root
```dockerfile
FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.4.30 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev

FROM python:3.12-slim AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PATH="/app/.venv/bin:$PATH"
RUN groupadd --system app && useradd --system --gid app --uid 10001 app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
USER app
EXPOSE 8000
HEALTHCHECK CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/health/live')"]
CMD ["uvicorn", "my_service.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
```

`README.md` is copied with the manifests because `pyproject.toml` declares `readme = "README.md"` and the build backend
reads it when the project is installed (drop it from the `COPY` if you do not declare a readme; keep it out of `.dockerignore`).
Dependencies are copied before source so the expensive layer is cached. The runtime stage has no
compiler, no uv, no dev dependencies, and runs as an unprivileged user. `.dockerignore` excludes
`.git`, `.venv`, `tests`, `__pycache__`, `.env*`.

## 4. Reproducibility and supply chain
- Commit `uv.lock`; `uv sync --locked` (or `uv lock --check`) fails CI on drift.
- Pin uv to one exact version in both places (`setup-uv` `version:` and the `ghcr.io/astral-sh/uv:<tag>` image) and bump them together.
- Pin the base image by major.minor (digest for release builds).
- Add `diff-cover>=9.0` (used by `completion-gate` for changed-line coverage) and `pip-audit>=2.7` to the dev dependency group and run `uv run pip-audit` (or Dependabot/Renovate) as a scheduled job for vulnerable dependencies.
- No secrets in images or build args; they arrive at runtime from the environment.

## Do / Don't
- ✅ One command per gate, identical locally and in CI.
- ✅ Cache on `uv.lock`, not on `pyproject.toml` alone.
- ✅ Run containers as a non-root user with a read-only filesystem where possible.
- ❌ `pip install` without a lock file, or `uv sync` without `--locked` in CI.
- ❌ `continue-on-error: true` on a quality gate.
- ❌ Single-stage images that ship build tools, tests or `.git`.
- ❌ `latest` tags for base images or actions.

## Cross-references
- `python-static-analysis` — the configuration behind the quality job's commands.
- `python-unit-tests`, `python-integration-tests` — the unit and integration jobs.
- `python-observability` — health endpoints and runtime telemetry for the container.
