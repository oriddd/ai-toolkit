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
last_reviewed: 2026-11-11
---

# CI Skill
This skill provisions the **CI** layer for a Java 21 / Spring Boot
microservice. It produces three vendor-neutral artifacts at the repo root:

1. `Jenkinsfile` — declarative pipeline (no shared library).
2. `Dockerfile` — multi-stage Spring Boot image with extracted layers,
   non-root user, public base image.
3. `pom.xml` — plain Spring Boot parent + the build plugins the rest of
   the skill catalogue relies on.

Pair with `github-actions-ci` by picking
**one** per repo, never both.

## 1. `pom.xml` — minimum shape

```xml
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>{{springBootVersion}}</version> <!-- latest Spring Boot 3.5.x -->
    <relativePath/>
  </parent>

  <groupId>{{groupId}}</groupId>
  <artifactId>{{artifactId}}</artifactId>
  <version>1.0.0-SNAPSHOT</version> <!-- rewritten by the release bot (release-versioning §4) -->

  <properties>
    <java.version>21</java.version>
    <maven.compiler.release>21</maven.compiler.release>
    <jacoco.version>0.8.12</jacoco.version> <!-- not managed by the Boot BOM; let Renovate bump it (Java 25 needs a newer release) -->
    <jacoco.minimum.line>0.85</jacoco.minimum.line>
    <jacoco.minimum.branch>0.75</jacoco.minimum.branch>
  </properties>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <!-- layered jar is the default since Boot 2.4; no <layers> configuration needed -->
      </plugin>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>${jacoco.version}</version>
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
                  <element>CLASS</element> <!-- per class: 85 % line / 75 % branch (unit-tests, quality-review) -->
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

Static-analysis plugins are added by
`static-analysis` — keep them out of
this skill so the two concerns evolve independently. The full
[`templates/pom.xml.tmpl`](./templates/pom.xml.tmpl) also carries Lombok, Failsafe, the
Jacoco excludes (bootstrap class, generated sources, JPA metamodel `*_`) and the PIT
mutation gate (≥ 75 %, guild #12; `unit-tests` explains it).

## 2. `Dockerfile` — multi-stage, layered, non-root

```dockerfile
# syntax=docker/dockerfile:1.7

# ---- stage 1: extract layers ----
FROM eclipse-temurin:21-jre-alpine AS layers
WORKDIR /app
# Exactly one jar must match. If the build also produces sources/javadoc jars,
# pass --build-arg JAR_FILE=target/{{artifactId}}-<version>.jar
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} app.jar
# Spring Boot 3.3+ "tools" jarmode (replaces the deprecated layertools, removed in Boot 4.1)
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted

# ---- stage 2: runtime ----
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S -g {{runAsGroup}} app && adduser -S -G app -u {{runAsUser}} app
# Optional: extra system packages
# RUN apk add --no-cache {{extraSystemPackages}}
WORKDIR /app
USER app

COPY --from=layers /app/extracted/dependencies/          ./
COPY --from=layers /app/extracted/spring-boot-loader/    ./
COPY --from=layers /app/extracted/snapshot-dependencies/ ./
COPY --from=layers /app/extracted/application/           ./

EXPOSE {{appPort}}

# MaxRAMPercentage sizes the heap from the container memory limit (the JVM default is only 25 %).
# MinRAMPercentage only applies to very small containers (< ~250 MB); it is not a minimum heap.
ENV JAVA_OPTS="-XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=512m -XX:MinRAMPercentage=25.0 -XX:MaxRAMPercentage=75.0"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
```

The block above is identical to [`templates/Dockerfile.tmpl`](./templates/Dockerfile.tmpl); edit both together.

Rules:

- **Non-root** (`USER app`, UID `{{runAsUser}}` and GID `{{runAsGroup}}`, default 1000 / 1000). They must match the
  Helm chart's `runAsUser` / `runAsGroup` in the hardened `securityContext` (see `cd`).
- **Layer extraction** uses `-Djarmode=tools extract --layers --launcher` (Spring Boot 3.3+). The old
  `-Djarmode=layertools` is deprecated and removed in Boot 4.1.
- **One jar in `target/`** — `COPY ${JAR_FILE}` fails if the build also produces sources/javadoc jars; then pass
  `--build-arg JAR_FILE=target/<artifactId>-<version>.jar`.
- **`JAVA_OPTS`** — `MaxRAMPercentage=75` sizes the heap from the container memory limit (the JVM default is 25 %).
- **Layered jar** — dependency changes don't invalidate the application
  layer, keeping image pushes small.
- **`JarLauncher`** — the Spring Boot 3.2+ entry point. Do not use
  `org.springframework.boot.loader.JarLauncher` (pre-3.2 path).
- **Base image** `eclipse-temurin:21-jre-alpine`; pinning a SHA in
  production is encouraged (managed by Renovate / Dependabot).

## 3. `Jenkinsfile` — declarative, vendor-neutral

```groovy
// Multibranch Pipeline job: enable "Discover tags" in the branch source, otherwise `tag 'v*'` never matches.
// Builds are triggered by the SCM webhook / branch indexing; add `triggers { pollSCM(...) }` only for a
// single-branch Pipeline job without webhooks (it is redundant in multibranch).
pipeline {
  agent { label 'maven-21' }
  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }
  environment {
    IMAGE_NAME = '{{imageRegistry}}/{{artifactId}}'
  }
  stages {
    stage('Commit messages') {
      when { changeRequest() }
      // Same check as the `commitlint` job (release-versioning §1, git-commit-conventions); needs Node.js on the agent
      steps {
        sh '''
          npx --yes -p @commitlint/cli -p @commitlint/config-conventional \\
            commitlint --from "origin/${CHANGE_TARGET}" --to HEAD --verbose
        '''
      }
    }
    stage('Build & test') {
      // `verify` runs unit + component tests (Surefire), integration tests (Failsafe) and the Jacoco `check`.
      // integration-tests policy: a PR that touches no `client/` package or repository may add -DskipITs;
      // `main` and tags always run them.
      steps { sh 'mvn -B -ntp -U clean verify' }
      post {
        always {
          junit testResults: '**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml', allowEmptyResults: true
          recordCoverage tools: [[parser: 'JACOCO']]
          archiveArtifacts artifacts: 'target/site/jacoco/**', allowEmptyArchive: true
        }
      }
    }
    stage('Dependency scan') {
      // OWASP dependency-check (security-hardening). Without an NVD API key the NVD download is throttled and very
      // slow: store the key as a Jenkins secret-text credential. The plugin reads it from the environment variable, so the
      // key never appears on the command line (`ps`) or in Maven debug output. Fails on CVSS >= 7.
      steps {
        withCredentials([string(credentialsId: '{{nvdApiKeyCredentialsId}}', variable: 'NVD_API_KEY')]) {
          sh 'mvn -B -ntp org.owasp:dependency-check-maven:check -DfailBuildOnCVSS=7 -DnvdApiKeyEnvironmentVariable=NVD_API_KEY'
        }
      }
    }
    stage('Container image') {
      when { anyOf { branch 'main'; tag 'v*' } }
      steps {
        script {
          // release-versioning §6: git tag v1.4.0 → image tag 1.4.0; main → build number
          // (deploy a main build with `--set image.tag=<build number>`; make registry tags immutable)
          env.IMAGE_TAG = env.TAG_NAME ? env.TAG_NAME.replaceFirst(/^v/, '') : env.BUILD_NUMBER
        }
        // The agent needs a Docker daemon (a mounted socket is root-equivalent); prefer a rootless
        // builder such as Kaniko, Buildah or rootless BuildKit where the platform offers one.
        withCredentials([usernamePassword(credentialsId: '{{registryCredentialsId}}',
                                          usernameVariable: 'REGISTRY_USER',
                                          passwordVariable: 'REGISTRY_PASSWORD')]) {
          sh '''
            echo "$REGISTRY_PASSWORD" | docker login "${IMAGE_NAME%%/*}" -u "$REGISTRY_USER" --password-stdin
            docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
            # Scan BEFORE pushing: HIGH/CRITICAL findings fail the build and nothing is published.
            # Needs the trivy CLI on the agent (pin its version), or run the pinned aquasec/trivy image.
            trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "${IMAGE_NAME}:${IMAGE_TAG}"
            docker push "${IMAGE_NAME}:${IMAGE_TAG}"
          '''
        }
      }
    }
  }
  post {
    // CHANGE_AUTHOR_EMAIL is only set on PR builds; culprits() also covers main and tag builds
    failure { mail to: emailextrecipients([culprits(), requestor()]), subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}", body: "${env.BUILD_URL}" }
  }
}
```

The block above is identical to [`templates/Jenkinsfile.tmpl`](./templates/Jenkinsfile.tmpl); edit both together.
Placeholders: `{{imageRegistry}}` (e.g. `ghcr.io/<org>`), `{{artifactId}}`, and `{{registryCredentialsId}}` (a Jenkins
username/password credential for the registry), `{{nvdApiKeyCredentialsId}}` (secret-text NVD API key for
dependency-check). The agent label `maven-21` stands for any Jenkins agent with JDK 21, Maven, Docker, Node.js and
Trivy — rename it to the label your Jenkins uses. The image is scanned with Trivy before it is pushed, failing on HIGH/CRITICAL (same policy as
`github-actions-ci`); pin the `dependency-check-maven` version in the pom's `pluginManagement` and the Trivy version on
the agent, both kept current by Renovate. Required Jenkins plugins: Pipeline, JUnit, Coverage, Credentials Binding,
Email Extension (for `emailextrecipients`). The `Commit messages` stage needs Node.js on the agent and the
`commitlint.config.mjs` from `release-versioning` §1 (`export default { extends: ['@commitlint/config-conventional'] };`)
at the repo root — the same file the GitHub `commitlint` action reads by default. It also needs `origin/<target branch>`
and the history back to the merge base: keep the checkout non-shallow, and if the branch source's PR strategy does not
fetch the target branch (it does when PRs are merged with the target), add `+refs/heads/*:refs/remotes/origin/*` to its
refspecs. `nvdApiKeyEnvironmentVariable` needs dependency-check-maven 10 or newer (verified on 13.0.0).

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
| Integration test phase split | `integration-tests` (Failsafe; reports published with Surefire's) |
| Commit-message check | `git-commit-conventions` (the `Commit messages` stage) |
| Dependency + image scan | `ci` (`Dependency scan` stage, Trivy before push; policy in `security-hardening`) |
| Image signing + SBOM | `security-hardening` (`ai-toolkit-java-build`, if installed) |
| Helm chart deployment | `cd` |
| Release versioning + tag | `release-versioning` (`ai-toolkit-workflow`) |

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
   Jacoco coverage `check` goal (`-DskipITs` skips only Failsafe, per the `integration-tests` policy).

## 5. Templates

- [`Dockerfile.tmpl`](./templates/Dockerfile.tmpl) — Multi-stage Spring Boot image.
- [`Jenkinsfile.tmpl`](./templates/Jenkinsfile.tmpl) — Declarative CI pipeline.
- [`pom.xml.tmpl`](./templates/pom.xml.tmpl) — Baseline Maven project file.
