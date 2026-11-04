---
name: sdk-publishing
description: Producer-side of the lego-brick principle. Turn an internal module into a reusable Spring Boot library / starter — auto-configuration with @ConditionalOnMissingBean defaults, configuration metadata for IDE autocomplete, semantic versioning, minimal API surface, deprecation policy. Use when extracting shared code into its own artifact (a "client SDK", a "domain library", an in-house starter).
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

```
my-foo-spring-boot-starter/
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

### `pom.xml`

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-autoconfigure</artifactId>
        <scope>provided</scope>          <!-- consumer brings Spring Boot -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-configuration-processor</artifactId>
        <optional>true</optional>        <!-- generates IDE metadata -->
    </dependency>
</dependencies>
```

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
module foo.spring.boot.starter {
    requires spring.context;
    requires spring.web;
    exports my.foo.api;
    exports my.foo.autoconfigure;
    // internal/ NOT exported
}
```

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
      "description": "Base URL of the Foo dependency. Required.",
      "defaultValue": "http://localhost:8080"
    }
  ]
}
```

## Versioning + deprecation policy

- **SemVer.** Major = breaking, minor = additive, patch = bug fix.
- **Deprecation window: 2 minor releases.** Mark with `@Deprecated(forRemoval = true, since = "1.4.0")`
  and provide a migration note in the CHANGELOG.
- **Never** change the wire shape of a DTO in a non-major bump.
- **Never** rename a `@ConfigurationProperties` key without keeping the old
  one as deprecated with `DeprecatedConfigurationProperty(replacement = "...")`.

## Testing

The library ships with its own tests:

- **Unit tests** for every API class.
- **`@SpringBootTest` slice** with `ApplicationContextRunner`:

```java
@Test
void registersBeansWhenWebClientPresent() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(FooAutoConfiguration.class))
        .withPropertyValues("foo.dependency.base-url=http://x")
        .run(ctx -> {
            assertThat(ctx).hasSingleBean(FooClient.class);
            assertThat(ctx).hasSingleBean(FooHealthIndicator.class);
        });
}

@Test
void backsOffWhenConsumerProvidesItsOwn() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(FooAutoConfiguration.class))
        .withUserConfiguration(CustomConfig.class)
        .withPropertyValues("foo.dependency.base-url=http://x")
        .run(ctx -> assertThat(ctx).hasBean("customFooClient"));
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
❌ Never depend on a Spring starter from a library — only on
`spring-boot-autoconfigure` (`provided`).
❌ Never break wire compatibility in a non-major release.
❌ Never extract code into a library before the rule of three is satisfied.

