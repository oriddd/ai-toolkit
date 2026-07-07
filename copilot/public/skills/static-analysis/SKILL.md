---
name: static-analysis
description: Mechanically enforce code style and catch bug classes — Spotless (formatter), SpotBugs (bug patterns), Error-Prone (compile-time bug patterns), NullAway (null-safety), Sonar quality profile, Checkstyle for organization-specific rules. Wires every tool into Maven so violations break the build. Use whenever a new repo is created.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Static Analysis Skill (public)

These tools complement the `quality-review` checklist by failing the build
on objective violations.

## Stack

| Tool | What it catches | Configured how |
| --- | --- | --- |
| **Spotless** | Formatting drift (indent, imports, blank lines) | `pom.xml` plugin + `.spotless.gradle`-style import order |
| **SpotBugs** + FindSecBugs | Bug patterns (null deref, resource leak, EI_EXPOSE_REP, SQLi, XSS) | Maven plugin, fail on HIGH |
| **Error-Prone** | Compile-time bug patterns from Google (NPE, mutable enum, missing override, …) | `-XepDisableWarningsInGeneratedCode` to silence noise |
| **NullAway** | Null-safety: every reference is annotated `@Nullable` or assumed non-null | Annotated packages only |
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
        <threshold>Low</threshold>
        <failOnError>true</failOnError>
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
            <version>2.28.0</version>
          </path>
          <path>
            <groupId>com.uber.nullaway</groupId>
            <artifactId>nullaway</artifactId>
            <version>0.11.0</version>
          </path>
        </annotationProcessorPaths>
        <compilerArgs>
          <arg>-XDcompilePolicy=simple</arg>
          <arg>-Xplugin:ErrorProne -XepDisableWarningsInGeneratedCode -Xep:NullAway:ERROR
               -XepOpt:NullAway:AnnotatedPackages={{basePackage}}</arg>
        </compilerArgs>
      </configuration>
    </plugin>
  </plugins>
</build>
```

## Spotless first, opinion second

- `mvn spotless:apply` is the **only** way to format code. IDE formatting
  is configured to match Spotless output — no debates in PR.
- Pre-commit runs `spotless:apply` automatically (see `local-dev-experience`).

## NullAway annotation policy

- Default-non-null for all `{{basePackage}}` packages. Mark any nullable
  return / param with `@Nullable`.
- Generated code (MapStruct mappers, JPA static metamodel) excluded by
  package.

## Suppressions

- `@SuppressWarnings("…")` only with a comment explaining **why**, reviewed
  in the PR.
- Project-wide suppressions live in a checked-in `spotbugs-exclude.xml`,
  reviewed periodically. Empty list is the goal.

## CI failure policy

| Tool | Fail build on |
| --- | --- |
| Spotless | Any difference |
| SpotBugs | Any HIGH; new MEDIUM versus baseline |
| Error-Prone / NullAway | Any new violation |
| Sonar | Quality Gate failure (default: > 5 % new code smells, < 80 % new-code coverage) |

## Do / Don't

✅ One canonical formatter (Spotless + google-java-format AOSP).
✅ Bug-finding tools run on every build; HIGH severity breaks the build.
✅ Every suppression has a comment + reviewer sign-off.
❌ Never disable a check globally to fix a single false-positive — narrow the
suppression to the smallest scope.
❌ Never check in re-formatted code in a PR that does anything else; ship
formatting changes as separate commits.

