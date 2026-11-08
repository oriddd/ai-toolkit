---
name: pluggable-architecture
description: >
  Java / Spring Boot ports and adapters — every external technology (cache, DB, broker, metrics, object store,
  secrets, identity) behind a port, with adapters chosen by configuration via conditional beans. Use before writing
  ANY code that talks to an external tool or technology.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [code-structure, spring-boot-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-30
---

# Pluggable Architecture Skill
The single most important architectural rule in this catalogue: **no business
code is ever coupled to a concrete technology.** Every integration with an
external tool — a cache, a database dialect, a metrics backend, a broker, an
object store, a secret manager, an identity provider, a feature-flag service —
is consumed through a **port** (a project-owned interface) and supplied by one
or more **adapters** (vendor-specific implementations) that are chosen **by
configuration**, never by editing code.

This is the **Ports & Adapters (Hexagonal)** pattern, hardened into a
non-negotiable and combined with Spring's conditional wiring so that:

- Any technology can be **swapped** for an alternative by changing a property
  (and/or a dependency on the classpath) — zero changes to domain/application
  code.
- A capability can run with **multiple providers at once** (broadcast,
  failover, priority, weighted) when the use case demands it — again by
  configuration only.
- The codebase reads like an **open-source SDK**: stable interfaces, replaceable
  internals, SOLID by construction (DIP + OCP enforced mechanically).

> This skill is the *policy*. Concrete skills (`persistence`, `observability`,
> `messaging`, `external-client`, `rate-limiting`, `data-privacy`, …) are the
> *bindings* — each one must expose its technology through a port that obeys the
> rules below.

## When to use

Apply this skill **whenever** a task introduces or modifies contact with an
external technology or third-party library. If the agent is about to type an
`import` for a vendor SDK (Redis, Datadog, Oracle JDBC, Kafka, AWS S3, …) in
anything other than an adapter (or its vendor `@Configuration` in the same
`adapter/<capability>/<vendor>/` package), **stop** and apply this skill first.

**Accepted facades.** Some Spring abstractions already *are* a vendor-neutral
port, and the other skills use them directly: Spring Data repository interfaces
(`persistence`; the dialect is swapped by driver + configuration) and the
Micrometer `MeterRegistry` / Observation API (`observability`, `request-metrics`;
the registry is the adapter). Do not wrap them in another port. The rule still
applies to the vendor types *behind* them (e.g. no JDBC-driver class or
backend-specific registry class imported in business code).

## 1. The three layers of every capability

For a capability named `X`, generate exactly three concerns in separate places:

```
<basePackage>/
├── spi/                                  # the PORT — owned by us, vendor-free
│   └── x/
│       ├── XPort.java                     # interface the domain depends on
│       ├── XKey.java / XResult.java …     # port DTOs (records), vendor-free
│       └── XProviderException.java        # port-level exception type
├── adapter/                               # the ADAPTERS — one sub-package per vendor
│   └── x/
│       ├── redis/   RedisXAdapter.java     # implements XPort using a vendor SDK
│       │            RedisXConfiguration.java  # vendor @Configuration (conditions + vendor beans)
│       ├── infinispan/ InfinispanXAdapter.java, InfinispanXConfiguration.java
│       └── noop/    NoOpXAdapter.java      # safe default / disabled mode (harmless capabilities only)
└── config/                                # the WIRING — conditional selection only
    └── x/
        └── XAutoConfiguration.java         # @Import(vendor configurations) + fallback; no vendor imports
```

Rules:

- **`spi/` (the port)** contains *only* project-owned types. **No vendor import
  is ever allowed here.** No `org.springframework.data.redis.*`, no
  `com.datadoghq.*`, no `oracle.jdbc.*`. The port speaks the project's
  language, not the vendor's.
- **`adapter/<capability>/<vendor>/`** is the *only* place a vendor SDK may be
  imported. It holds the adapter and a `public` vendor `@Configuration` class that
  creates the adapter bean. Because that configuration sits in the same package,
  the adapter itself can stay `package-private`.
- **`config/x/`** holds the conditional wiring and nothing else — no business
  logic, no vendor calls, no vendor imports: it `@Import`s the vendor
  configurations and declares the fallback, guarded by `@ConditionalOn…`.

## 2. The port contract (DIP + OCP)

```java
// spi/x/CachePort.java  — vendor-free, this is what the domain depends on
public interface CachePort {
    Optional<byte[]> get(CacheKey key);
    void put(CacheKey key, byte[] value, Duration ttl);
    void evict(CacheKey key);
    String providerId();           // for observability + composition routing
}

// spi/x/CacheKey.java — port DTO: a record of JDK types
public record CacheKey(String value) {
    public CacheKey { Objects.requireNonNull(value, "value"); }
}
```

- The port is the **stable contract**. It changes only on a deliberate, SemVer
  major decision (see `sdk-publishing`, `release-versioning`).
- Port method signatures use **port DTOs** (records) and JDK types — never
  vendor types, never framework types. An adapter that needs a vendor type
  *translates* at its own boundary (the Adapter pattern from
  `code-structure` §4j).
- The port carries a `providerId()` so logs, metrics, and composition policies
  can identify which brick handled a call.

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §3, §4, §5 | config-driven single provider, multi-provider composition, configuration shape | wiring or composing adapters | [`selection-and-composition.md`](./references/selection-and-composition.md) |
| §6, §7 | ArchUnit rules and the per-skill port/adapter map | enforcing the boundary or mapping another skill onto ports | [`enforcement-and-skill-map.md`](./references/enforcement-and-skill-map.md) |

## 8. Definition of done (per capability)

Before returning a diff that touches an external technology, verify:

- [ ] A **port interface** exists under `spi/<capability>/`, free of vendor and
      framework types.
- [ ] **1..N adapters** exist under `adapter/<capability>/<vendor>/`, each the
      *only* place its vendor SDK is imported.
- [ ] A **safe default** adapter (`NoOp` or local) is provided via
      `@ConditionalOnMissingBean` — **only** for harmless capabilities (cache,
      metrics, feature flags with coded defaults). Security-relevant capabilities
      (encryption, key provider, secrets, identity, permissions) get **no** NoOp
      default: a missing or misconfigured provider fails startup with a clear
      message.
- [ ] Selection/composition lives **only** in `config/<capability>/…` and is
      driven by a typed `@ConfigurationProperties` (enum provider key).
- [ ] Swapping providers requires **only** a property change (and optionally a
      dependency swap) — **no** domain/application edits.
- [ ] **Multi-provider mode** is either supported (with failure isolation) or
      explicitly documented as unsupported for that capability.
- [ ] **ArchUnit** rules from §6 cover the new capability and pass.
- [ ] **Contract tests** (see `adapter-contract-tests`) validate that *every*
      adapter satisfies the same port behaviour.
- [ ] `platform.<capability>.*` keys are documented in the README and in
      configuration metadata.

## Do / Don't

✅ Depend on a **port interface** from domain/application code — always.
✅ Put the **only** vendor import inside `adapter/<capability>/<vendor>/`.
✅ Select and compose providers **by configuration** (`@ConditionalOnProperty`
   + typed enum), with a `@ConditionalOnMissingBean` safe default for harmless
   capabilities.
❌ Never default a security capability (encryption, secrets, identity) to NoOp —
   fail fast at startup instead.
✅ Make every brick replaceable by a consumer-supplied bean of the same port
   type (lego-brick override).
✅ Support multi-provider fan-out via a **composite adapter**, with per-provider
   failure isolation.
✅ Enforce "no vendor leakage into `spi/`" with ArchUnit so it fails the build.
❌ Never import a vendor SDK in `service/`, `operation/`, `controller/`,
   `domain/`, or `spi/`.
❌ Never branch on the technology inside business logic
   (`if (provider == REDIS) …`) — that belongs in the composite/config layer.
❌ Never make the domain aware of *how many* providers are active.
❌ Never hard-wire a single vendor with `new RedisTemplate(...)` outside an
   adapter's vendor configuration.
❌ Never let a provider's failure in `broadcast` mode take down the others.

## Cross-references

- `code-structure` — package hierarchy, Adapter /
  Strategy patterns, ArchUnit enforcement this skill builds on.
- `spring-boot-conventions` — typed
  `@ConfigurationProperties` and `@Conditional*` wiring.
- `sdk-publishing` — producer-side lego-brick
  (`@ConditionalOnMissingBean` defaults, configuration metadata, SemVer).
- `external-client` — consumer-side adapter stack
  for a single downstream.
- `adapter-contract-tests` — TCK-style
  shared tests proving every adapter is interchangeable.
- `observability`,
  `persistence`,
  `messaging`,
  `rate-limiting` — capabilities that bind to this
  policy.

