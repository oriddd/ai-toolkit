---
name: local-dev-experience
description: >
  Java / Spring Boot inner loop in under 5 minutes — docker-compose for dependencies, Makefile/Justfile,
  .devcontainer, .editorconfig, pre-commit hooks (format, lint, fast tests, secrets scan). Use when a repo is created
  or local setup is slow or unreliable.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Local Dev Experience Skill
The cost of onboarding a new contributor is dominated by "how do I get this
running locally?". This skill makes the answer "`make up && make test`".

## 1. `docker-compose.yml` for downstream deps

Mirror the runtime topology in lightweight containers:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment: { POSTGRES_DB: foo, POSTGRES_USER: foo, POSTGRES_PASSWORD: foo }
    ports: ["127.0.0.1:5432:5432"]      # bind to loopback — the dev credentials are weak
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U foo"]
      interval: 5s

  kafka:
    image: confluentinc/cp-kafka:7.6.0
    environment: { … KRaft single-node config … }
    ports: ["127.0.0.1:9092:9092"]

  minio:
    image: minio/minio:<pinned-release-tag>   # pin a RELEASE.* tag — never latest
    command: server /data --console-address ":9001"
    environment: { MINIO_ROOT_USER: foo, MINIO_ROOT_PASSWORD: foopass }
    ports: ["127.0.0.1:9000:9000","127.0.0.1:9001:9001"]
```

Bring it up with `docker compose up -d` (wrapped by a Makefile target —
see below). Spring Boot's `application.yaml` defaults match these ports.

> **Spring Boot 3.1+ alternative:** add `spring-boot-docker-compose` as a
> dependency and Spring will start `docker-compose.yml` automatically when
> the app launches in dev mode. Powerful, but explicit `make up` is more
> predictable across IDEs / CI.

## 2. `Makefile` (or `Justfile`) — the canonical entry points

```makefile
.PHONY: up down reset build test it lint format precommit run logs

up:        ; docker compose up -d
down:      ; docker compose down            # keeps the volumes (your local data)
reset:     ; docker compose down -v         # also deletes the volumes — destroys local data
build:     ; mvn -B -q -DskipTests package
test:      ; mvn -B -q test
it:        ; mvn -B -q -Dgroups=integration verify
lint:      ; mvn -B -q spotless:check spotbugs:check
format:    ; mvn -B -q spotless:apply
precommit: format lint test
run:       ; mvn spring-boot:run
logs:      ; docker compose logs -f --tail=200
```

Discover targets with `make` (no args). Every project speaks the same verbs:
`up`, `down`, `build`, `test`, `it`, `lint`, `format`, `precommit`, `run`,
`logs`.

## 3. `.devcontainer/devcontainer.json`

```json
{
  "name": "{{artifactId}}",
  "image": "mcr.microsoft.com/devcontainers/java:21-bookworm",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/common-utils:2": {}
  },
  "postCreateCommand": "make up && mvn -B -q -DskipTests package",
  "customizations": {
    "vscode": { "extensions": ["vscjava.vscode-java-pack", "redhat.vscode-yaml"] }
  }
}
```

Open the repo in VS Code or JetBrains Gateway and the env is provisioned —
no "works on my machine".

## 4. `.editorconfig`

Already shipped by `create-repo`. Pin: `indent_style=space`, `indent_size=4`
(2 for YAML/JSON/MD), `end_of_line=lf`, `insert_final_newline=true`,
`trim_trailing_whitespace=true`.

## 5. `.pre-commit-config.yaml`

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks: [ {id: end-of-file-fixer}, {id: trailing-whitespace}, {id: check-yaml} ]
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks: [ {id: gitleaks} ]
  - repo: local
    hooks:
      - id: spotless
        name: spotless
        entry: mvn -q spotless:apply
        language: system
        pass_filenames: false
      - id: fast-tests
        name: fast tests
        entry: mvn -q -DskipTests=false test -Dtest='*Test' -DfailIfNoTests=false
        language: system
        pass_filenames: false
        stages: [pre-push]
```

Install once: `pre-commit install && pre-commit install --hook-type pre-push`.

## 6. IDE settings

Ship under `.idea/codeStyles/` (IntelliJ) or `.vscode/settings.json` so
formatting is identical across contributors. Spotless is the authoritative
formatter; IDE files only configure trivia (import order, line length).

## 7. Repo-level scripts (`bin/`)

For one-off automation that doesn't fit a Make target:
- `bin/seed-db.sh` — load realistic dev data into local Postgres.
- `bin/reset-broker.sh` — purge Kafka topics.
- `bin/bump-bom.sh` — bump a shared BOM and run tests.

Each script starts with `#!/usr/bin/env bash` followed by `set -euo pipefail` on the
next line, and has a help banner.

## Do / Don't

✅ One repo, one `make up`. If a contributor needs to read more than the
README to start the app, the inner loop is broken.
✅ Pin every dev tool version in the Makefile / pre-commit config — no
"latest".
✅ Mirror prod topology in compose with the **same image families** (e.g.
  `postgres:16-alpine`, not an embedded H2).
❌ Never check in IDE per-user files (`*.iws`, workspace.xml). Ship shared
codestyle only.
❌ Never depend on a manually-configured local install of a database / broker
— compose it.

