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
last_reviewed: 2026-11-11
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
    image: apache/kafka:<pinned-release-tag>   # official image, single-node KRaft (no ZooKeeper); never latest
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092   # what the app on the host connects to
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@localhost:9093
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
    ports: ["127.0.0.1:9092:9092"]
    healthcheck:
      test: ["CMD-SHELL", "/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1"]
      interval: 10s
      retries: 10

  minio:
    image: minio/minio:<pinned-release-tag>   # pin a RELEASE.* tag — never latest (see the note below)
    command: server /data --console-address ":9001"
    environment: { MINIO_ROOT_USER: foo, MINIO_ROOT_PASSWORD: foopass }
    ports: ["127.0.0.1:9000:9000","127.0.0.1:9001:9001"]
```

Bring it up with `docker compose up -d` (wrapped by a Makefile target —
see below). Put the matching dev URLs and the weak dev credentials in `application-local.yaml` (or a git-ignored
`.env`), never in the base `application.yaml` — the base file must not carry credentials (golden-path #16).

> **MinIO status:** MinIO stopped publishing community container images in late 2025 and the community edition is
> in maintenance mode, so a pinned `minio/minio` tag no longer receives fixes. For a local S3 stand-in, prefer a
> maintained S3-compatible image (e.g. LocalStack S3, SeaweedFS or Garage) and keep the app on the plain S3 API.

> **Spring Boot 3.1+ alternative:** add `spring-boot-docker-compose` as a
> dependency and Spring will start `docker-compose.yml` automatically when
> the app launches in dev mode. Powerful, but explicit `make up` is more
> predictable across IDEs / CI.

## 2. `Makefile` (or `Justfile`) — the canonical entry points

```makefile
.PHONY: help up down reset build test it lint format precommit run logs
.DEFAULT_GOAL := help

help:      ## list the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'
up:        ; docker compose up -d                     ## start the dependencies
down:      ; docker compose down                      ## stop them, keep the volumes (your local data)
reset:     ; docker compose down -v                   ## stop them and delete the volumes — destroys local data
build:     ; ./mvnw -B -q -DskipTests package         ## build the jar
test:      ; ./mvnw -B -q test                        ## unit + component tests
it:        ; ./mvnw -B -q test-compile failsafe:integration-test failsafe:verify   ## integration tests only (needs Docker)
lint:      ; ./mvnw -B -q compile spotless:check spotbugs:spotbugs spotbugs:check   ## format + bug checks (compile first: SpotBugs reads classes)
format:    ; ./mvnw -B -q spotless:apply              ## format the code
precommit: format lint test                           ## what the hooks run
run:       ; ./mvnw spring-boot:run -Dspring-boot.run.profiles=local   ## run against the compose deps
logs:      ; docker compose logs -f --tail=200        ## follow the dependency logs
```

`it` calls the Failsafe goals directly: `-Dgroups=integration verify` would also filter out every unit and component
test while the JaCoCo and PIT gates still run, so the gate fails (`integration-tests`, "CI integration").

Discover targets with `make` (no args runs `help`). Every project speaks the same verbs:
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
  "postCreateCommand": "./mvnw -B -q -DskipTests package",
  "postStartCommand": "make up",
  "customizations": {
    "vscode": { "extensions": ["vscjava.vscode-java-pack", "redhat.vscode-yaml"] }
  }
}
```

Open the repo in VS Code or JetBrains Gateway and the env is provisioned —
no "works on my machine". The commands use the Maven wrapper (`./mvnw`, committed by `create-repo`), so the image
needs no Maven install; `make up` runs on every container start, the build only once on creation.

## 4. `.editorconfig`

Already shipped by `create-repo` (`ai-toolkit-java-scaffold`, if installed). Pin: `indent_style=space`, `indent_size=4`
(2 for YAML/JSON/MD), `end_of_line=lf`, `insert_final_newline=true`,
`trim_trailing_whitespace=true`.

## 5. `.pre-commit-config.yaml`

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: <pinned-tag>   # e.g. a v5.x release; `pre-commit autoupdate` bumps it
    hooks: [ {id: end-of-file-fixer}, {id: trailing-whitespace}, {id: check-yaml} ]
  - repo: https://github.com/gitleaks/gitleaks
    rev: <pinned-tag>   # a current v8.x release
    hooks: [ {id: gitleaks} ]
  - repo: local
    hooks:
      - id: spotless
        name: spotless
        entry: ./mvnw -q spotless:apply
        language: system
        pass_filenames: false
      - id: fast-tests
        name: fast tests
        entry: ./mvnw -q -DskipTests=false test -Dtest='*Test,!*ComponentTest' -Dsurefire.failIfNoSpecifiedTests=false
        language: system
        pass_filenames: false
        stages: [pre-push]
```

`*Test` alone also matches `*ComponentTest` (a full Spring context per class); the `!` pattern keeps the pre-push
hook to the fast unit tests. Install once: `pre-commit install && pre-commit install --hook-type pre-push`.
Keep the `rev:` pins current with `pre-commit autoupdate` (or Renovate's `pre-commit` manager), never by hand.

## 6. IDE settings

Ship under `.idea/codeStyles/` (IntelliJ) or `.vscode/settings.json` so
formatting is identical across contributors. The rest of `.idea/` and `.vscode/` stays ignored: the `create-repo`
`.gitignore` uses `.idea/*` + `!.idea/codeStyles/` and `.vscode/*` + `!.vscode/settings.json` (a plain `.idea/` would
ignore the shared files too). Spotless is the authoritative
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

