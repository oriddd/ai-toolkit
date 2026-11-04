---
name: ci
description: >
  Java 21 / Spring Boot CI with Jenkins — declarative Jenkinsfile, multi-stage Dockerfile, Maven build. Use when
  bootstrapping a repo or moving a service onto a standard Jenkins pipeline. For GitHub Actions use
  `github-actions-ci`.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [static-analysis]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# CI Skill
This skill provisions the **CI** layer for a Java 21 / Spring Boot
microservice. It produces three vendor-neutral artifacts at the repo root:

1. `Jenkinsfile` — declarative pipeline (no shared library).
2. `Dockerfile` — multi-stage Spring Boot image with extracted layers,
   non-root user, public base image.
3. `pom.xml` — plain Spring Boot parent + the build plugins the rest of
   the skill catalogue relies on.

Pair with [`github-actions-ci`](../github-actions-ci/SKILL.md) by picking
**one** per repo, never both.

## 1. `pom.xml` — minimum shape

```xml
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>{{springBootVersion}}</version> <!-- a currently supported Spring Boot release -->
    <relativePath/>
  </parent>

  <groupId>{{basePackage}}</groupId>
  <artifactId>{{serviceName}}</artifactId>
  <version>0.1.0-SNAPSHOT</version>

  <properties>
    <java.version>21</java.version>
    <maven.compiler.release>21</maven.compiler.release>
    <jacoco.minimum.line>0.80</jacoco.minimum.line>
    <jacoco.minimum.branch>0.70</jacoco.minimum.branch>
  </properties>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <layers><enabled>true</enabled></layers>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <executions>
          <execution>
            <goals><goal>prepare-agent</goal></goals>
          </execution>
          <execution>
            <id>report</id>
            <phase>verify</phase>
            <goals><goal>report</goal><goal>check</goal></goals>
            <configuration>
              <rules>
                <rule>
                  <element>BUNDLE</element>
                  <limits>
                    <limit><counter>LINE</counter>   <minimum>${jacoco.minimum.line}</minimum></limit>
                    <limit><counter>BRANCH</counter> <minimum>${jacoco.minimum.branch}</minimum></limit>
                  </limits>
                </rule>
              </rules>
            </configuration>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
```

Static-analysis + mutation-testing plugins are added by
`static-analysis` and
`unit-tests` respectively — keep them out of
this skill so the two concerns evolve independently.

## 2. `Dockerfile` — multi-stage, layered, non-root

```dockerfile
# syntax=docker/dockerfile:1.7

# ---- stage 1: extract layers ----
FROM eclipse-temurin:21-jre-alpine AS layers
WORKDIR /app
COPY target/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# ---- stage 2: runtime ----
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S -G app -u 10001 app
WORKDIR /app
USER app

COPY --from=layers /app/dependencies/         ./
COPY --from=layers /app/spring-boot-loader/   ./
COPY --from=layers /app/snapshot-dependencies/ ./
COPY --from=layers /app/application/          ./

EXPOSE 8080
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

Rules:

- **Non-root** (`USER app`, UID 10001). Required for the Helm chart's
  hardened `securityContext` (see [`cd`](../cd/SKILL.md)).
- **Layered jar** — dependency changes don't invalidate the application
  layer, keeping image pushes small.
- **`JarLauncher`** — the Spring Boot 3.2+ entry point. Do not use
  `org.springframework.boot.loader.JarLauncher` (pre-3.2 path).
- **Base image** `eclipse-temurin:21-jre-alpine`; pinning a SHA in
  production is encouraged (managed by Renovate / Dependabot).

## 3. `Jenkinsfile` — declarative, vendor-neutral

```groovy
pipeline {
  agent { label 'maven-21' }
  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }
  triggers { pollSCM('H/5 * * * *') }
  stages {
    stage('Build & test') {
      steps { sh 'mvn -B -ntp -U clean verify' }
      post {
        always {
          junit testResults: '**/target/surefire-reports/*.xml', allowEmptyResults: true
          recordCoverage tools: [[parser: 'JACOCO']]
        }
      }
    }
    stage('Container image') {
      when { anyOf { branch 'main'; tag 'v*' } }
      steps {
        sh '''
          IMAGE_TAG="${BRANCH_NAME == 'main' ? 'latest' : env.TAG_NAME}"
          docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
          docker push "${IMAGE_NAME}:${IMAGE_TAG}"
        '''
      }
    }
  }
  post {
    failure { mail to: '${CHANGE_AUTHOR_EMAIL}', subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}", body: "${env.BUILD_URL}" }
  }
}
```

This pipeline is **deliberately vanilla** — no `@Library('…')` import,
no custom DSL, no environment-specific image registry. You can replace
the `Build & test` and `Container image` stages in your own codebase with
a one-line call to a shared library — this skill stays vendor-neutral so
it remains portable.

## 4. Wiring with other skills

| Concern | Owned by |
| --- | --- |
| Code coverage threshold | `ci` (jacoco-maven-plugin `check`) |
| Formatter / linter / NullAway | `static-analysis` |
| Mutation testing | `unit-tests` (PIT) |
| Integration test phase split | `integration-tests` (Failsafe) |
| Image signing + SBOM | `security-hardening` |
| Helm chart deployment | [`cd`](../cd/SKILL.md) |
| Release versioning + tag | `release-versioning` |

## Do / Don't

✅ Pin the base image SHA in production-critical pipelines.
✅ Keep the Dockerfile multi-stage so the runtime image carries only the
JRE + the layered application.
✅ Run the pipeline as a non-root container; the Helm chart enforces this.
❌ Never hard-code environment-specific registries, shared libraries,
or codeowners in this skill — keep such bindings in your own
codebase, not in the shared catalogue.
❌ Never use Spring Boot's old `JarLauncher` path
(`o.s.b.loader.JarLauncher`) on Spring Boot 3.2+.
❌ Never skip `mvn verify` in PR builds — `verify` is what runs the
   Jacoco coverage `check` goal.

## 5. Templates

- [`Dockerfile.tmpl`](./templates/Dockerfile.tmpl) — Multi-stage Spring Boot image.
- [`Jenkinsfile.tmpl`](./templates/Jenkinsfile.tmpl) — Declarative CI pipeline.
- [`pom.xml.tmpl`](./templates/pom.xml.tmpl) — Baseline Maven project file.
