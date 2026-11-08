---
name: sonar-quality-gate
description: >
  Drive the SonarQube/SonarCloud new-code quality gate to green — bugs, vulnerabilities, smells, hotspots,
  duplication, coverage — without suppressing findings; report honestly if Sonar is unreachable. Use when the
  completion gate reaches Sonar or a pipeline's Sonar gate fails.
tier: should
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Sonar Quality Gate Skill
## When to use

Sonar judges **new code** (the diff against the base branch). Run it after build, tests and static
analysis are green, because it consumes their reports (coverage, test results).

## 1. Discover the setup

Look for, in this order: `sonar-project.properties`, `sonar.*` properties in `pom.xml`/`build.gradle`/`package.json`,
a Sonar stage in `Jenkinsfile`/CI workflows. Take project key, host and base branch from there.
If a Sonar skill or MCP is installed, prefer it over raw `curl`.

If there is no Sonar configuration, report "Sonar: not configured" — do not add one unprompted.

## 2. Credentials

- Host and token come from the environment (`SONAR_HOST_URL`, `SONAR_TOKEN`). Never write a token into a
  file, a command line you echo, a commit or a report. Current scanners read `SONAR_TOKEN` themselves, so do **not**
  pass `-Dsonar.token=…` (visible in the process list); servers older than 10.0 need `sonar.login`, SonarCloud also
  needs `sonar.organization`.
- No token or the server is unreachable → report **not verified** with the reason, stop at §5, do not retry in a loop.

## 3. Run the analysis

**Default: read the CI result.** When CI already analyses the branch or PR, read its gate status (§4) instead of
running an analysis. A local analysis uploads to a shared server, so run one only after the developer confirms it.

With that confirmation, generate coverage first (the `completion-gate` commands), then:

```bash
# Maven (token from the SONAR_TOKEN environment variable; pin the plugin version, here or in pluginManagement)
mvn -B verify org.sonarsource.scanner.maven:sonar-maven-plugin:<version>:sonar -Dsonar.qualitygate.wait=true -Dsonar.host.url="$SONAR_HOST_URL"
# Any other stack
sonar-scanner -Dsonar.qualitygate.wait=true -Dsonar.host.url="$SONAR_HOST_URL"
```

Point Sonar at the coverage report the tests produced, or new-code coverage reads 0 and the gate fails:

| Language | Property |
| --- | --- |
| Java | `sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml` |
| Python | `sonar.python.coverage.reportPaths=coverage.xml` (`pytest --cov --cov-report=xml`) |
| TypeScript / React Native | `sonar.javascript.lcov.reportPaths=coverage/lcov.info` (`jest --coverage`) |

Add the branch or pull-request parameters the project's pipeline uses so the results match CI
(`-Dsonar.branch.name=<branch>`, or `-Dsonar.pullRequest.key/branch/base` for a PR).
**Warning:** a run without them is published as the main-branch analysis and overwrites the shared result
everyone else sees. If the server has no branch support (Community Edition), do not run a local analysis
against the shared project — ask the developer, or rely on the CI result.
`sonar.qualitygate.wait=true` makes the command fail when the gate fails.

## 4. Read and fix the result

Gate status: `GET $SONAR_HOST_URL/api/qualitygates/project_status?projectKey=<key>&branch=<branch>` (or `&pullRequest=<id>`
for a PR — without one the main-branch status is returned, which can show a false green).
Open new-code issues: `GET /api/issues/search?components=<key>&resolved=false&inNewCodePeriod=true&branch=<branch>`
(or `&pullRequest=<id>`; without either it returns main-branch issues, a false green)
(`componentKeys` on older servers; `sinceLeakPeriod=true` instead of `inNewCodePeriod` on older servers).

Fix every failing condition at its cause:

| Finding | Fix |
| --- | --- |
| Bug / vulnerability | Correct the code |
| Security hotspot | Fix it, or explain and ask the developer to review it — never self-approve |
| Code smell | Refactor (complexity, duplication, naming) |
| Duplication | Extract or reuse |
| New-code coverage below the gate | Add meaningful tests for the uncovered branches (`code-hygiene` §2) — never padding |

Re-run from the build step after each round.

## 5. Report

Gate status, number of new issues by type, new-code coverage and duplication, and the project key/branch analysed.
When not run: `Sonar: not verified — <reason>`, plus the local proxies that did pass (static analysis, coverage report, duplication).

## Don't

- ❌ Mark issues Won't Fix / False Positive, resolve them in the UI, or add `//NOSONAR`.
- ❌ Exclude files or lower the gate, profile or thresholds to get green.
- ❌ Commit analysis output, `.scannerwork/`, or tokens.
- ❌ Upload a local analysis to the shared server without the developer's confirmation.
- ✅ Fix the code; if a rule is genuinely wrong for this repo, tell the developer and let them decide.

## Cross-references

`completion-gate`, `code-hygiene`, and per language the static-analysis skill (`static-analysis`, `python-static-analysis`, `react-native-static-analysis`).
