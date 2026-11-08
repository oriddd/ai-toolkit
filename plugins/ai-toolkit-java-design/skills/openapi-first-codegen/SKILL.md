---
name: openapi-first-codegen
description: >
  Java / Spring Boot OpenAPI-first — generate controllers and DTOs from api.yaml with openapi-generator-maven-plugin,
  exclude generated code from coverage and analysis, keep generated DTOs inside the controller. Use when the spec
  should be the single source of truth.
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
        <!-- a dedicated `generated` package, so exclusions never hit hand-written `api` packages -->
        <apiPackage>{{basePackage}}.generated.api</apiPackage>
        <modelPackage>{{basePackage}}.generated.api.model</modelPackage>
        <configOptions>
          <useSpringBoot3>true</useSpringBoot3>      <!-- also switches imports to jakarta.* (useJakartaEe) -->
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

Pin the generator version in `<properties>` and let Renovate bump it.
`invokerPackage` is omitted on purpose: with `interfaceOnly=true` the generator emits no invoker classes.

## 3. Static-analysis / coverage exclusions

Generated code is verbatim and reviewed via the spec, not the Java diff.
Add to the relevant plugins (paths are repo-relative):

| Plugin | Exclusion |
| --- | --- |
| **Jacoco** (`jacoco-maven-plugin`)         | `<exclude>**/generated/api/**</exclude>` in the `<configuration><excludes>` block (covers `generated/api/model/` too). |
| **Spotless**                                | `<excludes><exclude>target/generated-sources/**</exclude></excludes>` inside the `<java>` block. |
| **SpotBugs / FindSecBugs**                  | `<excludeFilterFile>` referencing a filter that matches `{{basePackage}}.generated.api.**`. |
| **ArchUnit** (in tests)                     | Exclude **by package**: generated and hand-written classes both compile to `target/classes`, so a path filter on `target/generated-sources/**` matches nothing. Use `ImportOption.DoNotIncludeArchives` plus a custom `ImportOption` such as `location -> !location.contains("/generated/api/")`, or `.resideOutsideOfPackage("..generated.api..")` in each rule. |
| **NullAway / Error-Prone**                  | `-XepExcludedPaths:.*/generated-sources/.*`. |
| **Sonar (optional)**                        | `sonar.coverage.exclusions=**/generated/api/**`, `sonar.exclusions=**/generated/api/**`. |

Without these, every spec change inflates the coverage delta and triggers
false-positive findings.

## 4. Controller pattern

```java
@RestController
@RequiredArgsConstructor
class FooController implements FooApi {                    // FooApi is generated

    private final FooService service;
    private final FooResponseMapper mapper;                // hand-written, in mapper/

    @Override
    public ResponseEntity<FooResponse> getFoo(UUID id) {   // signature comes from FooApi (`format: uuid` → UUID)
        Foo domain = service.findById(EntityId.of(id));
        return ResponseEntity.ok(mapper.toResponse(domain));
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
  controller. Convert at the boundary using a hand-written `*ResponseMapper`
  (and `*RequestMapper`) in `mapper/` — the same "remote DTOs stay at the boundary" rule as `external-client`.

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
| API design rules the spec must satisfy            | `api-design` |
| Generic Spring Boot conventions (springdoc note)  | `spring-boot-conventions` §5 |
| ProblemDetail error contract referenced from spec | `exception-handling` |
| Controllers wired to domain services              | `code-structure` |
| Publishing a generated client SDK                 | `sdk-publishing` |
| Multipart endpoints (file + JSON DTO)             | `api-design` §6b |

## Do / Don't

| ✅ Do | ❌ Don't |
| --- | --- |
| Treat `api.yaml` as the single source of truth. | Maintain Swagger annotations on controllers in the same module. |
| Exclude `target/generated-sources/**` from every analysis tool. | Let generated DTOs leak into services or repositories. |
| Use `interfaceOnly=true` and hand-write controllers. | Use `generateApiTests=true` — those tests are tautological. |
| Pin the generator version. | Rely on the transitive default version from the plugin chain. |
| Add a CI step that fails on stale generated sources (run `mvn clean verify` so sources are regenerated from `api.yaml` and a controller out of step with the spec fails the compile — they are git-ignored, so `git diff --exit-code` cannot detect drift). | Commit `target/` or the `.openapi-generator-ignore` overrides without review. |
| Reference shared `ProblemDetail` schema for every error response. | Inline `{ "message": "..." }` ad-hoc error shapes. |

