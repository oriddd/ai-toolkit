---
name: static-analysis
description: >
  Java / Spring Boot static analysis wired into Maven so violations break the build — Spotless, SpotBugs, Error-Prone,
  NullAway, Checkstyle, Sonar profile. Use when a repo is created or a lint, format or analysis rule is added or
  fails.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Static Analysis Skill
These tools complement the `quality-review` checklist by failing the build
on objective violations.

## Stack

| Tool | What it catches | Configured how |
| --- | --- | --- |
| **Spotless** | Formatting drift (indent, imports, blank lines) | `pom.xml` plugin with an `<importOrder>` block |
| **SpotBugs** + FindSecBugs | Bug patterns (null deref, resource leak, EI_EXPOSE_REP, SQLi, XSS) | Maven plugin, threshold Medium; fail on any HIGH and any MEDIUM not in the baseline |
| **Error-Prone** | Compile-time bug patterns from Google (NPE, mutable enum, missing override, …) | `-XepExcludedPaths` skips generated sources (`-XepDisableWarningsInGeneratedCode` only silences warnings) |
| **NullAway** | Null-safety: every reference is annotated `@Nullable` or assumed non-null | Annotated packages only |
| **Checkstyle** | Team-specific rules: method length, file length, parameter count (`quality-review` F22–F24) | `maven-checkstyle-plugin` + checked-in `checkstyle.xml` |
| **PMD** (optional) | Method/class size, complexity (overlaps with `quality-review`) | Often dropped in favour of SpotBugs + Sonar |
| **Sonar** (optional) | Aggregated quality dashboard, hotspots | CI step that uploads to SonarCloud / SonarQube |

## Maven wiring

```xml
<build>
  <plugins>
    <plugin>
      <groupId>com.diffplug.spotless</groupId>
      <artifactId>spotless-maven-plugin</artifactId>
      <version>2.43.0</version>
      <configuration>
        <java>
          <googleJavaFormat><version>1.22.0</version><style>AOSP</style></googleJavaFormat>
          <removeUnusedImports/>
          <importOrder><order>java,javax,jakarta,org,com,</order></importOrder>
        </java>
        <pom><sortPom/></pom>
      </configuration>
      <executions><execution><goals><goal>check</goal></goals></execution></executions>
    </plugin>

    <plugin>
      <groupId>com.github.spotbugs</groupId>
      <artifactId>spotbugs-maven-plugin</artifactId>
      <version>4.8.6.4</version>
      <configuration>
        <effort>Max</effort>
        <threshold>Medium</threshold>          <!-- Low would fail the build on every minor finding -->
        <failOnError>true</failOnError>
        <excludeFilterFile>spotbugs-exclude.xml</excludeFilterFile>   <!-- the baseline: known findings, reviewed periodically -->
        <plugins>
          <plugin>
            <groupId>com.h3xstream.findsecbugs</groupId>
            <artifactId>findsecbugs-plugin</artifactId>
            <version>1.13.0</version>
          </plugin>
        </plugins>
      </configuration>
      <executions><execution><goals><goal>check</goal></goals></execution></executions>
    </plugin>

    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-compiler-plugin</artifactId>
      <configuration>
        <annotationProcessorPaths>
          <path>
            <groupId>com.google.errorprone</groupId>
            <artifactId>error_prone_core</artifactId>
            <version>2.36.0</version>   <!-- or newer; 2.36+ needs the should-stop arg below -->
          </path>
          <path>
            <groupId>com.uber.nullaway</groupId>
            <artifactId>nullaway</artifactId>
            <version>0.12.0</version>   <!-- or newer -->
          </path>
          <!-- Listing processors here disables classpath discovery: every processor the build uses must be listed -->
          <path>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>   <!-- managed by the Spring Boot parent -->
          </path>
        </annotationProcessorPaths>
        <compilerArgs>
          <!-- Error Prone on JDK 17+/21 also needs the --add-exports / --add-opens flags from the note below -->
          <arg>-XDcompilePolicy=simple</arg>
          <arg>--should-stop=ifError=FLOW</arg>   <!-- required by Error Prone 2.36+ -->
          <!-- ExcludedPaths: openapi-generated models would otherwise fail NullAway at ERROR (golden-path #14).
               ExcludedFieldAnnotations: fields injected by Mockito / Spring (incl. @Value) are never null.
               ExternalInitAnnotations: JPA fills entity fields after the no-arg constructor (persistence). -->
          <arg>-Xplugin:ErrorProne -XepDisableWarningsInGeneratedCode
               -XepExcludedPaths:.*/target/generated-sources/.*
               -Xep:NullAway:ERROR
               -XepOpt:NullAway:AnnotatedPackages={{basePackage}}
               -XepOpt:NullAway:UnannotatedSubPackages={{basePackage}}.generated
               -XepOpt:NullAway:TreatGeneratedAsUnannotated=true
               -XepOpt:NullAway:ExcludedFieldAnnotations=org.mockito.Mock,org.mockito.Spy,org.mockito.InjectMocks,org.mockito.Captor,org.springframework.beans.factory.annotation.Autowired,org.springframework.beans.factory.annotation.Value,org.springframework.boot.test.web.server.LocalServerPort,org.springframework.test.context.bean.override.mockito.MockitoBean
               -XepOpt:NullAway:ExternalInitAnnotations=jakarta.persistence.Entity,jakarta.persistence.Embeddable,jakarta.persistence.MappedSuperclass</arg>
        </compilerArgs>
      </configuration>
    </plugin>

    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-checkstyle-plugin</artifactId>
      <version>3.4.0</version>
      <dependencies>
        <dependency>
          <groupId>com.puppycrawl.tools</groupId>
          <artifactId>checkstyle</artifactId>
          <version>10.17.0</version>
        </dependency>
      </dependencies>
      <configuration>
        <configLocation>checkstyle.xml</configLocation>
        <consoleOutput>true</consoleOutput>
        <failOnViolation>true</failOnViolation>
        <violationSeverity>error</violationSeverity>   <!-- warnings (F22, F24) are printed, errors (F23 ceiling) fail -->
      </configuration>
      <executions><execution><phase>validate</phase><goals><goal>check</goal></goals></execution></executions>
    </plugin>
  </plugins>
</build>
```

Minimal checked-in `checkstyle.xml` enforcing the `quality-review` F22–F24
thresholds (add team-specific modules below these). The severities match
quality-review: F22 and F24 are **WARN** there, so Checkstyle reports them
without failing the build; only the F23 **hard ceiling** (300 lines) is an
error. The plugin configuration above uses `<violationSeverity>error</violationSeverity>`,
so warnings are printed but do not break the build:

```xml
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
    "https://checkstyle.org/dtds/configuration_1_3.dtd">
<module name="Checker">
  <property name="severity" value="warning"/>
  <!-- F23 class length: hard ceiling 300 breaks the build (the 200 target is checked in quality-review) -->
  <module name="FileLength">
    <property name="max" value="300"/>
    <property name="severity" value="error"/>
  </module>
  <module name="TreeWalker">
    <!-- F22 method length (WARN) -->
    <module name="MethodLength">
      <property name="max" value="30"/>
      <property name="countEmpty" value="false"/>
    </module>
    <!-- F24 method parameters (WARN); constructors excluded: Spring beans take their collaborators there -->
    <module name="ParameterNumber">
      <property name="max" value="4"/>
      <property name="ignoreOverriddenMethods" value="true"/>
      <property name="tokens" value="METHOD_DEF"/>
    </module>
  </module>
</module>
```

Starter `spotbugs-exclude.xml` (the baseline the plugin above references —
without the file the build fails). At threshold Medium, SpotBugs flags
`EI_EXPOSE_REP*` and `CT_CONSTRUCTOR_THROW` on most Spring beans, which hold
injected collaborators and validate in constructors by design, and
`UUF_UNUSED_PUBLIC_OR_PROTECTED_FIELD` on every JPA static-metamodel class (`Invoice_`) that `hibernate-jpamodelgen`
generates (`persistence`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
  <!-- Spring beans keep references to injected (shared, immutable-by-contract) collaborators -->
  <Match><Bug pattern="EI_EXPOSE_REP,EI_EXPOSE_REP2"/></Match>
  <!-- constructors that reject invalid configuration are intended -->
  <Match><Bug pattern="CT_CONSTRUCTOR_THROW"/></Match>
  <!-- generated sources (openapi-first-codegen), golden-path #14 -->
  <Match><Package name="~{{basePackage}}\.generated(\..*)?"/></Match>
  <!-- JPA static metamodel generated by hibernate-jpamodelgen (Invoice_), persistence -->
  <Match><Class name="~.*_"/></Match>
</FindBugsFilter>
```

## Spotless first, opinion second

- `mvn spotless:apply` is the **only** way to format code. IDE formatting
  is configured to match Spotless output — no debates in PR.
- Pre-commit runs `spotless:apply` automatically (see `local-dev-experience`).
- Run `mvn spotless:apply` once after generating a repo or any code (the
  `sortPom` step also reorders the generated `pom.xml`); otherwise the first
  `spotless:check` fails on generated, unformatted files.

## NullAway annotation policy

- Default-non-null for all `{{basePackage}}` packages. Mark any nullable
  return / param with JSpecify `org.jspecify.annotations.Nullable` — one `@Nullable` flavour per repo. The Spring Boot
  3.5 BOM does not manage it, so declare the version:
  ```xml
  <dependency><groupId>org.jspecify</groupId><artifactId>jspecify</artifactId><version>1.0.0</version></dependency>
  ```
- Generated code (openapi models, MapStruct mappers, JPA static metamodel)
  excluded by path (`-XepExcludedPaths`) and package
  (`UnannotatedSubPackages`).
- JPA entities (`@Entity`, `@Embeddable`, `@MappedSuperclass`) are listed in `ExternalInitAnnotations`: JPA sets their
  fields after the protected no-arg constructor, so NullAway skips that constructor but still checks every other
  constructor initialises the non-null fields. Columns that may be null are `@Nullable`; never exclude entities
  from NullAway altogether (`ExcludedClassAnnotations`). The `persistence` entities also mark that constructor
  `@SuppressWarnings("NullAway.Init")`, which works without this option; keep both — the option covers entities
  written without the suppression.
- Test code: fields injected by Mockito / Spring (`@Autowired`, `@Value`, `@MockitoBean`, …) are excluded via
  `ExcludedFieldAnnotations` (above). Alternatively keep Error Prone out of
  test compilation by giving the `default-testCompile` execution its own
  `compilerArgs` without `-Xplugin:ErrorProne`.

## Suppressions

- `@SuppressWarnings("…")` only with a comment explaining **why**, reviewed
  in the PR.
- Project-wide suppressions live in a checked-in `spotbugs-exclude.xml`,
  reviewed periodically. Empty list is the goal.

**JDK 17+ / 21:** Error Prone runs inside javac and needs access to compiler internals. Put these in `.mvn/jvm.config` (one line), or the
build fails with `IllegalAccessError`:

```
--add-exports jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.model=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.comp=ALL-UNNAMED
```

## CI failure policy

| Tool | Fail build on |
| --- | --- |
| Spotless | Any difference |
| SpotBugs | Any HIGH; any MEDIUM not in the `spotbugs-exclude.xml` baseline (HIGH findings are never baselined) |
| Checkstyle | Any `error`-severity violation (the F23 hard ceiling); F22 / F24 are printed as warnings, matching `quality-review` |
| Error-Prone / NullAway | Any violation (at `ERROR` there is no baseline) |
| Sonar | Quality Gate failure (default "Sonar way", on new code: reliability, security and maintainability rating A, all security hotspots reviewed, coverage ≥ 80 %, duplicated lines ≤ 3 %) |

## Do / Don't

✅ One canonical formatter (Spotless + google-java-format AOSP).
✅ Bug-finding tools run on every build; HIGH severity (and any MEDIUM not in the baseline) breaks the build.
✅ Every suppression has a comment + reviewer sign-off.
❌ Never disable a check globally to fix a single false-positive — narrow the
suppression to the smallest scope.
❌ Never check in re-formatted code in a PR that does anything else; ship
formatting changes as separate commits.

