---
name: project-types
description: >
  Java / Spring Boot meta-skill — picks the skill set for the kind of service: synchronous REST, event-driven,
  scheduler/batch, library/SDK, or monolith with microservice bones. Use as the entry point before invoking
  `create-repo`.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: true
version: 1.0
last_reviewed: 2026-06-28
---

# Project Types Skill (meta)

The skills are atomic; this skill tells you **which subset** to
apply for which kind of project. Run me first; I will pick the right
combination of skills and call `create-repo` with the right answers.

## 1. Type matrix

| Project type | What it does | Required skills | Optional skills |
| --- | --- | --- | --- |
| **A. Synchronous REST microservice** | HTTP API in front of business logic | `ci`, `cd`, `code-structure`, `spring-boot-conventions`, `exception-handling`, `permissions`, `external-client`, `health-indicator`, `api-design`, `security-hardening`, `observability`, `unit-tests`, `component-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `local-dev-experience`, `static-analysis`, `graceful-shutdown`, `input-validation`, `pluggable-architecture`, `resilience-patterns`, `request-metrics`, `context-maintenance` | `persistence`, `messaging`, `integration-tests`, `domain-modeling`, `adapter-contract-tests` (required once a port has an adapter, guild #21), `data-privacy` (required when the service handles personal data) |
| **B. Event-driven service** | Consumes from broker, may publish — no HTTP API | A minus the HTTP-API skills (`api-design`, `permissions`) + `messaging` (mandatory) + `persistence` (almost always) + `integration-tests` | `api-design`, `permissions` (only if a tiny status/admin HTTP API exists) |
| **C. Scheduler / batch job** | `@Scheduled` or one-shot CLI, no HTTP | `ci`, `cd`, `code-structure`, `spring-boot-conventions`, `exception-handling`, `external-client`, `observability`, `unit-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `local-dev-experience`, `static-analysis`, `graceful-shutdown`, `pluggable-architecture`, `resilience-patterns`, `context-maintenance`, `health-indicator` (long-running `@Scheduled` deployments on Kubernetes) | `persistence`, `adapter-contract-tests` |
| **D. Library / SDK** | Reusable JAR consumed by other services | `code-structure`, `spring-boot-conventions`, `exception-handling`, `external-client` (if it wraps a remote service), `sdk-publishing` (mandatory), `unit-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `static-analysis` | `permissions` if the library brings auth bits |
| **E. Monolith with microservice bones** | Single deployable that owns multiple bounded contexts but is structured so future split is cheap | A + `domain-modeling` (mandatory) + `messaging` (intra-process events via `ApplicationEventPublisher`, future-proof for broker) | n/a |

## 2. Decision flow

```
Is it deployed on its own, or is the JAR consumed by other JVM apps?
├── Consumed as a dependency → Type D (library / SDK)
└── Deployed → Does the service expose HTTP?
          ├── No → Does it consume events / messages?
          │         ├── Yes → Type B (event-driven)
          │         └── No  → Does it run on a schedule / once?
          │                   ├── Yes → Type C (scheduler / batch)
          │                   └── No  → reconsider the shape
          └── Yes → Does it own more than one bounded context?
                    ├── Yes → Type E (monolith with bones)
                    └── No  → Type A (sync REST)
```

## 3. Architectural style

Independent of project type, pick one **internal architectural style** per
service. Currently shipped:

- **Layered** (controller → operation → service → client) — default; see
  `code-structure`.
- **Hexagonal / Ports & Adapters** for the whole service — optional variant
  (no dedicated skill yet; build on `pluggable-architecture`).

Whichever style you pick, every external technology still sits behind a
project-owned port — that part is mandatory (golden-path #20,
`pluggable-architecture`).

Document the choice in an ADR (see `documentation-and-adr`).

## 4. Orchestration

This skill calls `create-repo` (HITL) and pre-fills its Phase 1 answers
(`create-repo` question numbers in brackets) based on the project type. Items
without a question number are not create-repo questions: they select which
create-repo Phase 3 steps run (persistence and messaging are routed from the
dependency types in [#16], see create-repo step 6a).

```
Type A (sync REST):
  [#9a] projectKind: service
  [#9]  auth / permissions: yes
  [#11] external-client: ask per dep
  [#16] dependencies: ask (Postgres → persistence, Kafka → messaging)
  api-design: yes

Type B (event-driven):
  [#9a] projectKind: service
  [#9]  auth / permissions: typically no (broker auth handles it)
  [#16] dependencies: broker (→ messaging) + DB (→ persistence, outbox)
  api-design: only if /actuator + admin

Type C (scheduler):
  [#9a] projectKind: service
  [#9]  auth / permissions: no
  [#10] requestMetrics: no (observability: include cron lag metric)
  api-design: no
  one-shot run (not a long-running @Scheduled pod): the cd chart's
  Deployment + HPA + probes would crash-loop a process that exits — replace
  them with a Kubernetes `Job` / `CronJob` manifest (no HPA, no probes);
  the `cd` skill ships no Job template, so write it by hand

Type D (library):
  [#9a] projectKind: library → ci: pom only (no Dockerfile, no image
        stages, no spring-boot repackage); cd: skip (no Helm chart)
  sdk-publishing: yes
  exception-handling: API-only (no advice)

Type E (monolith):
  [#9a] projectKind: service
  domain-modeling: yes
  messaging: yes (Spring events + outbox-ready)
```

## 5. Renaming guidance

| Component | Type A | Type B | Type C |
| --- | --- | --- | --- |
| Entry point | `controller/` | `consumer/` | `scheduler/` (`@Scheduled` beans) |
| Orchestrator | `operation/` | `handler/` | `job/` |
| Business logic | `service/` | `service/` | `service/` |
| Outbound | `client/` | `producer/` + `client/` | `client/` |

The rest of the package hierarchy from `code-structure` applies identically,
and the renamed packages take the place of their Type A counterpart in the
ArchUnit layer rules and in `quality-review` B6.

## Do / Don't

✅ Run me before `create-repo` so the right skills are pre-selected.
✅ Document the chosen project type in `docs/ARCHITECTURE.md` so future
maintainers don't have to reverse-engineer it.
❌ Never mix project types in one repo (HTTP API **and** scheduler **and**
event consumer all in one deployable) — split them, share via libraries.
❌ Never "upgrade" a Type C scheduler to a Type A REST service by bolting on
controllers — start a new repo.

