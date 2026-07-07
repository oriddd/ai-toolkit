---
name: openapi-first-codegen
description: >
  Drive controllers and DTOs from an OpenAPI 3 contract at the repo root
  (`api.yaml`) using `openapi-generator-maven-plugin`. Covers the plugin
  setup (Spring Boot 3 / Jakarta), where generated sources land, how to
  exclude them from coverage and static analysis, the
  `controller implements <ApiName>Api` pattern, and the rule that generated
  DTOs may never leak past the controller. Use when a service exposes an
  HTTP API and wants the spec to be the single source of truth.
tier: should
applies_to: [rest]
depends_on: [api-design]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# openapi-first-codegen

## When to use

- Adding a new HTTP API to a Spring Boot 3 / Java 21 service.
- The team agrees the **OpenAPI spec is the source of truth** (no annotation-
  driven specs, no hand-edited generated files).
- You want PRs that change the API to be reviewable as YAML diffs.

If you instead want to **document** an annotation-driven API at runtime, use
`spring-boot-conventions` §5 (springdoc) — that is the code-first track and
is mutually exclusive with this skill within the same module.

## Layout

```
<repo>/
├── api.yaml                              # single source of truth
├── pom.xml                               # generator plugin pinned
└── src/main/java/{{basePackagePath}}/
    └── controller/
        └── FooController.java            # implements FooApi (generated)
```

Generated sources land under `target/generated-sources/openapi/` (the Maven
default for the plugin). They MUST be:

- on the compile classpath via `build-helper-maven-plugin` (or the
  generator's `addCompileSourceRoot` flag, true by default);
- **excluded** from Jacoco, Spotless, SpotBugs/FindBugs, ArchUnit, NullAway,
  and any custom static-analysis rules;
- **never** edited by hand. If something is wrong, fix the spec.

## 1. `api.yaml` contract rules

- `openapi: 3.0.3` (or 3.1; pick one and stick with it).
- `info.version` follows the **service SemVer**, not the spec SemVer. Bump
  with the release.
- Every operation has a unique `operationId` in `lowerCamelCase` — that is
  the generated controller method name.
- Every operation lists `tags: [<resource>]`. The tag becomes the generated
  `<Resource>Api` interface name.
- Every 4xx / 5xx response references the shared `ProblemDetail` schema
  (see `exception-handling` skill) — never inline error shapes.
- Reusable schemas under `components/schemas`; primitive aliases under
  `components/schemas` too (e.g. `EntityId: { type: string, format: uuid }`).

## 2. Plugin block (`pom.xml`)

```xml
<plugin>
  <groupId>org.openapitools</groupId>
  <artifactId>openapi-generator-maven-plugin</artifactId>
  <version>${openapi-generator.version}</version>
  <executions>
    <execution>
      <id>generate-api</id>
      <goals><goal>generate</goal></goals>
      <configuration>
        <inputSpec>${project.basedir}/api.yaml</inputSpec>
        <generatorName>spring</generatorName>
        <library>spring-boot</library>
        <apiPackage>{{basePackage}}.api</apiPackage>
        <modelPackage>{{basePackage}}.api.model</modelPackage>
        <invokerPackage>{{basePackage}}.api.invoker</invokerPackage>
        <configOptions>
          <useSpringBoot3>true</useSpringBoot3>
          <useJakartaEe>true</useJakartaEe>
          <interfaceOnly>true</interfaceOnly>          <!-- controllers stay hand-written -->
          <useTags>true</useTags>
          <skipDefaultInterface>true</skipDefaultInterface>
          <useOptional>false</useOptional>
          <openApiNullable>false</openApiNullable>
          <dateLibrary>java8</dateLibrary>
          <serializableModel>false</serializableModel>
          <hideGenerationTimestamp>true</hideGenerationTimestamp>
        </configOptions>
      </configuration>
    </execution>
  </executions>
</plugin>
```

Pin the generator version in `<properties>` and let dependency-management
bump it.

## 3. Static-analysis / coverage exclusions

Generated code is verbatim and reviewed via the spec, not the Java diff.
Add to the relevant plugins (paths are repo-relative):

| Plugin | Exclusion |
| --- | --- |
| **Jacoco** (`jacoco-maven-plugin`)         | `<exclude>**/api/**</exclude>` and `<exclude>**/api/model/**</exclude>` in the `<configuration><excludes>` block. |
| **Spotless**                                | `<excludes><exclude>target/generated-sources/**</exclude></excludes>` inside the `<java>` block. |
| **SpotBugs / FindSecBugs**                  | `<excludeFilterFile>` referencing a filter that matches `{{basePackage}}.api.**`. |
| **ArchUnit** (in tests)                     | `ImportOption.DoNotIncludeArchives` plus a custom `ImportOption` that drops `target/generated-sources/**`. |
| **NullAway / Error-Prone**                  | `-XepExcludedPaths:.*/generated-sources/.*`. |
| **Sonar (optional)**                        | `sonar.coverage.exclusions=**/api/**`, `sonar.exclusions=**/api/**`. |

Without these, every spec change inflates the coverage delta and triggers
false-positive findings.

## 4. Controller pattern

```java
@RestController
@RequiredArgsConstructor
class FooController implements FooApi {                    // FooApi is generated

    private final FooService service;
    private final FooDtoAdapter adapter;                   // hand-written

    @Override
    public ResponseEntity<FooResponse> getFoo(String id) { // signature comes from FooApi
        Foo domain = service.findById(EntityId.of(id));
        return ResponseEntity.ok(adapter.toResponse(domain));
    }
}
```

Rules:
- Controllers **only** implement generated interfaces. No `@GetMapping` /
  `@PostMapping` on the controller class — those live on the generated
  `FooApi` interface.
- Controllers contain **zero business logic**. Delegate to a domain
  service. (See `code-structure`.)
- Generated DTOs (`FooRequest`, `FooResponse`) **must not leak** past the
  controller. Convert at the boundary using a hand-written `*DtoAdapter` —
  same Adapter rule as `external-client`.

## 5. Hygiene

- `mvn clean` before commits that change `api.yaml` — stale generated
  sources have caused real production bugs (mixed-version DTOs).
- Generated sources are **git-ignored** (`target/` is already ignored).
- Do **not** commit the `target/generated-sources/openapi/.openapi-generator/`
  state files.
- If the spec ships to consumers, publish `api.yaml` itself (and optionally
  a generated SDK via `sdk-publishing`) — never publish the generated
  server stubs.

## 6. Integration with related skills

| Concern | Skill |
| --- | --- |
| API design rules the spec must satisfy            | [`api-design`](../api-design/SKILL.md) |
| Generic Spring Boot conventions (springdoc note)  | [`spring-boot-conventions`](../spring-boot-conventions/SKILL.md) §5 |
| ProblemDetail error contract referenced from spec | [`exception-handling`](../exception-handling/SKILL.md) |
| Controllers wired to domain services              | [`code-structure`](../code-structure/SKILL.md) |
| Publishing a generated client SDK                 | [`sdk-publishing`](../sdk-publishing/SKILL.md) |
| Multipart endpoints (file + JSON DTO)             | [`api-design`](../api-design/SKILL.md) §6b |

## Do / Don't

| ✅ Do | ❌ Don't |
| --- | --- |
| Treat `api.yaml` as the single source of truth. | Maintain Swagger annotations on controllers in the same module. |
| Exclude `target/generated-sources/**` from every analysis tool. | Let generated DTOs leak into services or repositories. |
| Use `interfaceOnly=true` and hand-write controllers. | Use `generateApiTests=true` — those tests are tautological. |
| Pin the generator version. | Rely on the transitive default version from the plugin chain. |
| Add a CI step that fails on stale generated sources (run `mvn generate-sources` and `git diff --exit-code`). | Commit `target/` or the `.openapi-generator-ignore` overrides without review. |
| Reference shared `ProblemDetail` schema for every error response. | Inline `{ "message": "..." }` ad-hoc error shapes. |

