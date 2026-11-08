---
name: sdk-publishing
description: >
  Java / Spring Boot library or starter — auto-configuration with @ConditionalOnMissingBean defaults, configuration
  metadata, minimal API surface, semantic versioning, deprecation policy. Use when extracting shared code into its own
  artifact (client SDK, domain library, in-house starter).
tier: should
applies_to: [library]
depends_on: [release-versioning, static-analysis]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# SDK Publishing Skill
Companion to the `external-client` skill (which is the **consumer** side).
This skill describes how to **produce** a lego brick that other services can
depend on without surprises.

## When to extract a module

Extract when **all** of the following are true:

- The same code (or near-duplicate) appears in **≥ 3 services**.
- The code has a **stable contract** that has not changed in two minor
  releases.
- The code has its **own tests**, independent of any one consumer.
- A clear **owner team** can commit to a versioning + deprecation policy.

If any condition fails, keep the code in-service (the "rule of three") —
extracting too early creates worse coupling than duplication.

## Artifact shape

Follow Spring Boot's own convention: the code lives in an **`-autoconfigure`** module, and a thin
**`-starter`** module (a `pom.xml` with dependencies only, no code) is what consumers add.

```
foo-spring-boot-starter/            # thin: depends on foo-spring-boot-autoconfigure (+ any libraries it needs at runtime)
└── pom.xml
foo-spring-boot-autoconfigure/      # all the code below
├── pom.xml                   # packaging = jar
└── src/main/
    ├── java/<basePackage>/
    │   ├── api/              # public interfaces + DTOs (the contract)
    │   ├── internal/         # implementations (public classes in a package that is not exported / documented as internal)
    │   └── autoconfigure/
    │       └── FooAutoConfiguration.java
    └── resources/META-INF/
        ├── spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
        └── additional-spring-configuration-metadata.json
```

### `pom.xml` (autoconfigure module)

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-autoconfigure</artifactId>
        <scope>provided</scope>          <!-- consumer brings Spring Boot -->
    </dependency>
    <dependency>
        <groupId>org.springframework</groupId>
        <artifactId>spring-webflux</artifactId>
        <optional>true</optional>        <!-- WebClient: compiles FooClientImpl; @ConditionalOnClass(WebClient.class) backs off without it -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-configuration-processor</artifactId>
        <optional>true</optional>        <!-- generates IDE metadata -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-actuator</artifactId>
        <optional>true</optional>        <!-- compiles FooHealthIndicator; active only when the consumer has actuator -->
    </dependency>
</dependencies>

<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <configuration>
                <!-- JDK 23+ no longer runs processors found on the classpath: declare it explicitly -->
                <annotationProcessorPaths>
                    <path>
                        <groupId>org.springframework.boot</groupId>
                        <artifactId>spring-boot-configuration-processor</artifactId>
                    </path>
                </annotationProcessorPaths>
            </configuration>
        </plugin>
    </plugins>
</build>
```

The configuration processor generates the IDE metadata (`spring-configuration-metadata.json`). Whether
`annotationProcessorPaths` picks its version from `dependencyManagement` depends on your
`maven-compiler-plugin` version — if the build complains, add an explicit `<version>` matching your Spring Boot
version. If you also use Lombok, list it in `annotationProcessorPaths` too.

> **Boot 4 note:** `HealthIndicator` moved to the `spring-boot-health` module
> (`org.springframework.boot.health.contributor`); depend on that instead of `spring-boot-actuator` there.

Never package `spring-boot-starter-web` (or any starter) as a transitive
dependency — the consumer chooses their own web stack.

## Auto-configuration

```java
@AutoConfiguration
@ConditionalOnClass(WebClient.class)
@EnableConfigurationProperties(FooProperties.class)
public class FooAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public FooClient fooClient(WebClient.Builder builder, FooProperties props) {
        return new FooClientImpl(builder.baseUrl(props.baseUrl()).build(), props);
    }

    // Optional integration in a nested class: the outer class is only guarded by WebClient, so a bean method returning an actuator type
    // directly in it would fail with NoClassDefFoundError when actuator is not on the consumer's classpath.
    @Configuration(proxyBeanMethods = false)
    @ConditionalOnClass(HealthIndicator.class)
    static class HealthConfiguration {
        @Bean
        @ConditionalOnMissingBean
        public FooHealthIndicator fooHealthIndicator(FooClient client) {
            return new FooHealthIndicator(client);
        }
    }
}
```

Register it:
```
src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
─────────────────────────────────────────────────────────────────────────────
{{basePackage}}.autoconfigure.FooAutoConfiguration
```

### Rules

- **Every** library bean is `@ConditionalOnMissingBean`. Consumers can
  replace any default with their own implementation by declaring a same-type
  bean.
- **Every** auto-configuration is guarded by `@ConditionalOnClass` so the
  library is silently no-op when its prerequisites are absent.
- **Never** auto-configure a bean whose presence has security or cost
  implications (caching, async pools, schedulers) without an
  `@ConditionalOnProperty(prefix = "...", name = "enabled", havingValue = "true")`
  opt-in.

## Public API surface

The `api/` package contains:
- Interfaces (`FooClient`, `FooHealthSource`, …) — **never** concrete classes.
- DTOs as `record`s with explicit `@JsonProperty` names (so future Jackson
  defaults can't break the wire).
- A single `*Properties` `@ConfigurationProperties` record.
- A single `*Exception` hierarchy.

The `internal/` package contains every implementation. The auto-configuration lives in a *different* package (`autoconfigure`), so these classes
must be `public` to be instantiated there — package-private would not compile. Keep consumers out by **not exporting** the package (JPMS
`exports` list, or an `@API(status = INTERNAL)` / Javadoc `@hidden` marker) and by never returning an `internal` type from `api/`.

Use **JPMS** (`module-info.java`) when feasible to make this mechanical:

```java
module {{basePackage}} {
    requires spring.core;
    requires spring.beans;
    requires spring.context;
    requires spring.boot;
    requires spring.boot.autoconfigure;
    requires static spring.webflux;          // WebClient (optional dependency)
    requires static spring.boot.actuator;    // HealthIndicator (optional dependency)
    exports {{basePackage}}.api;
    exports {{basePackage}}.autoconfigure;
    // Spring instantiates and proxies the configuration and internal beans reflectively
    opens {{basePackage}}.autoconfigure to spring.core, spring.beans, spring.context;
    opens {{basePackage}}.internal to spring.core, spring.beans, spring.context;
    // internal/ NOT exported
}
```

Spring jars are automatic modules on the module path; check their names against the versions you use. If the
consumer runs on the class path (the usual case), `module-info` only documents intent — the
`api/` vs `internal/` split and the review rule still do the work.

## Configuration metadata for IDE autocomplete

`spring-boot-configuration-processor` reads `@ConfigurationProperties`
annotations at compile time and emits
`META-INF/spring-configuration-metadata.json`. Add a hand-written
`additional-spring-configuration-metadata.json` for descriptions:

```json
{
  "properties": [
    {
      "name": "foo.dependency.base-url",
      "type": "java.lang.String",
      "description": "Base URL of the Foo dependency. Required."
    }
  ]
}
```

A required property has **no** default (a `localhost` default silently points production at nothing). Enforce
it on the record:

```java
@Validated
@ConfigurationProperties(prefix = "foo.dependency")
public record FooProperties(@NotBlank String baseUrl) {}
```

## Versioning + deprecation policy

- **SemVer.** Major = breaking, minor = additive, patch = bug fix.
- **Deprecation window: 2 minor releases.** Mark with `@Deprecated(forRemoval = true, since = "1.4.0")`
  and provide a migration note in the CHANGELOG. (This is the **library** API; a service's public HTTP
  endpoints follow `api-design`'s deprecation window.)
- **Never** change the wire shape of a DTO in a non-major bump.
- **Never** rename a `@ConfigurationProperties` key without keeping the old
  one as deprecated. `@DeprecatedConfigurationProperty` goes on a getter, which a properties **record**
  doesn't have, so declare the deprecation in `additional-spring-configuration-metadata.json`:

```json
{ "properties": [ {
    "name": "foo.dependency.url",
    "type": "java.lang.String",
    "deprecation": { "replacement": "foo.dependency.base-url", "level": "warning" }
} ] }
```

## Testing

The library ships with its own tests:

- **Unit tests** for every API class.
- **Auto-configuration tests** with `ApplicationContextRunner` (not `@SpringBootTest`, and not a slice: it starts
  a minimal context with only the configurations you list):

```java
// WebClientAutoConfiguration supplies the WebClient.Builder bean fooClient needs; actuator (optional dependency above)
// must be on the test classpath for the HealthConfiguration branch.
@Test
void fooAutoConfiguration_webClientPresent_registersBeans() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(WebClientAutoConfiguration.class, FooAutoConfiguration.class))
        .withPropertyValues("foo.dependency.base-url=http://x")
        .run(ctx -> {
            assertThat(ctx).hasSingleBean(FooClient.class);
            assertThat(ctx).hasSingleBean(FooHealthIndicator.class);
        });
}

@Test
void fooAutoConfiguration_consumerDefinesFooClient_backsOff() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(WebClientAutoConfiguration.class, FooAutoConfiguration.class))
        .withUserConfiguration(CustomConfig.class)
        .withPropertyValues("foo.dependency.base-url=http://x")
        .run(ctx -> {
            assertThat(ctx).hasSingleBean(FooClient.class);        // only the consumer's one…
            assertThat(ctx).hasBean("customFooClient");
            assertThat(ctx).doesNotHaveBean("fooClient");           // …the library's default backed off
        });
}

@Configuration(proxyBeanMethods = false)
static class CustomConfig {
    @Bean
    FooClient customFooClient() {
        return mock(FooClient.class);
    }
}
```

These prove the lego-brick contract: the bean is created **only** when
needed and **gives way** to the consumer's override.

## Release pipeline

- Library has its own repo + its own `ci` (semver-aware: derive version from
  git tags).
- Publish to Maven Central / your artifact registry.
- BOM-friendly: expose the artifact via your BOM so consumers can
  inherit one version.

## Do / Don't

✅ One library = one bounded concept. If you can't summarise the library in
one sentence, split it.
✅ Every auto-configured bean is `@ConditionalOnMissingBean` + guarded by
`@ConditionalOnClass`.
✅ The public API is interfaces + records only; implementations live in
`internal/`.
✅ Configuration metadata is published so IDEs autocomplete.
❌ Never depend on a Spring starter from a library's autoconfigure module — only on
`spring-boot-autoconfigure` (`provided`) and optional libraries. Your own thin `-starter`
module depends on your `-autoconfigure` module.
❌ Never break wire compatibility in a non-major release.
❌ Never extract code into a library before the rule of three is satisfied.

