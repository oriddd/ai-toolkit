---
name: project-types
description: Meta-skill — picks the right combination of public skills for the **kind** of project being created. Covers four canonical microservice shapes (synchronous REST, event-driven, scheduler / batch, library / SDK) plus a "monolith-with-microservice-bones" starter. Use as the entry point before invoking `create-repo`.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: true
version: 1.0
last_reviewed: 2026-06-28
---

# Project Types Skill (public — meta)

The public skills are atomic; this skill tells you **which subset** to
apply for which kind of project. Run me first; I will pick the right
combination of skills and call `create-repo` with the right answers.

## 1. Type matrix

| Project type | What it does | Required skills | Optional skills |
| --- | --- | --- | --- |
| **A. Synchronous REST microservice** | HTTP API in front of business logic | `ci`, `cd`, `code-structure`, `spring-boot-conventions`, `exception-handling`, `permissions`, `external-client`, `health-indicator`, `api-design`, `security-hardening`, `observability`, `unit-tests`, `component-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `local-dev-experience`, `static-analysis`, `graceful-shutdown` | `persistence`, `messaging`, `integration-tests`, `domain-modeling` |
| **B. Event-driven service** | Consumes from broker, may publish — no HTTP API | A + `messaging` (mandatory) + `persistence` (almost always) + `integration-tests` | `api-design` (only if a tiny status/admin HTTP API exists) |
| **C. Scheduler / batch job** | `@Scheduled` or one-shot CLI, no HTTP | `ci`, `cd`, `code-structure`, `spring-boot-conventions`, `exception-handling`, `external-client`, `observability`, `unit-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `local-dev-experience`, `static-analysis`, `graceful-shutdown` | `persistence`, `health-indicator` (k8s readiness only) |
| **D. Library / SDK** | Reusable JAR consumed by other services | `code-structure`, `spring-boot-conventions`, `exception-handling`, `external-client` (if it wraps a remote service), `sdk-publishing` (mandatory), `unit-tests`, `quality-review`, `release-versioning`, `documentation-and-adr`, `static-analysis` | `permissions` if the library brings auth bits |
| **E. Monolith with microservice bones** | Single deployable that owns multiple bounded contexts but is structured so future split is cheap | A + `domain-modeling` (mandatory) + `messaging` (intra-process events via `ApplicationEventPublisher`, future-proof for broker) | n/a |

## 2. Decision flow

```
Does the service expose HTTP?
├── No → Does it consume events / messages?
│         ├── Yes → Type B (event-driven)
│         └── No  → Does it run on a schedule / once?
│                   ├── Yes → Type C (scheduler / batch)
│                   └── No  → reconsider — pure libraries are Type D
├── Yes → Is the JAR consumed by other JVM apps (not deployed alone)?
│         ├── Yes → Type D (library / SDK)
│         └── No  → Does it own more than one bounded context?
│                   ├── Yes → Type E (monolith with bones)
│                   └── No  → Type A (sync REST)
```

## 3. Architectural style

Independent of project type, pick one **internal architectural style** per
service. Currently shipped:

- **Layered** (controller → operation → service → client) — default; see
  `code-structure`.
- **Hexagonal / Ports & Adapters** — optional variant (forthcoming
  `hexagonal-architecture` skill).

Document the choice in an ADR (see `documentation-and-adr`).

## 4. Orchestration

This skill calls `create-repo` (HITL) and pre-fills the answer set based on
the project type:

```
Type A (sync REST):
  permissions: yes
  external-client: ask per dep
  persistence: ask
  messaging: ask
  api-design: yes

Type B (event-driven):
  api-design: only if /actuator + admin
  messaging: yes
  persistence: yes (outbox)
  permissions: typically no (broker auth handles it)

Type C (scheduler):
  api-design: no
  permissions: no
  observability: include cron lag metric

Type D (library):
  ci: yes (but no Helm chart)
  cd: skip
  sdk-publishing: yes
  exception-handling: API-only (no advice)

Type E (monolith):
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

The rest of the package hierarchy from `code-structure` applies identically.

## Do / Don't

✅ Run me before `create-repo` so the right skills are pre-selected.
✅ Document the chosen project type in `docs/ARCHITECTURE.md` so future
maintainers don't have to reverse-engineer it.
❌ Never mix project types in one repo (HTTP API **and** scheduler **and**
event consumer all in one deployable) — split them, share via libraries.
❌ Never "upgrade" a Type C scheduler to a Type A REST service by bolting on
controllers — start a new repo.

