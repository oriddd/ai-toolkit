---
name: react-native-e2e-tests
description: >
  React Native end-to-end tests with Maestro — stable test IDs, deterministic test data, a clear E2E vs unit split.
  Use when a critical user journey needs device-level verification or a flow is flaky. Component and hook logic lives
  in `react-native-unit-tests`.
tier: should
applies_to: [mobile]
depends_on: [react-native-unit-tests, react-native-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# React Native E2E Tests Skill
## When to use

Use for a small set of **critical journeys** that need the real app on a simulator or device:
sign-in, purchase, onboarding, deep-link entry. Everything else is cheaper and more reliable as a unit test.

## Layout

```
.maestro/
├── config.yaml
├── flows/
│   ├── sign-up.yaml
│   ├── sign-in.yaml
│   ├── place-order.yaml
│   └── deep-link-order.yaml
└── subflows/
    └── launch-signed-out.yaml
```

## Dependencies

Maestro is a standalone CLI (no npm dependency). **Installing it is a manual, developer-run step, done once per
workstation or CI image. An agent never runs an installer or pipes a download into a shell; if Maestro is
missing, tell the developer.** Prefer Homebrew, or the official installer pinned to a version you reviewed:

```sh
brew tap mobile-dev-inc/tap && brew install mobile-dev-inc/tap/maestro       # developer-run
# or, developer-run, pinned (never an unpinned "latest"):
# export MAESTRO_VERSION=<pinned-version>; curl -Ls "https://get.maestro.mobile.dev" | bash
```

Record the pinned version in the repo (README or `.maestro/config.yaml` comment) and in the CI image, then run:

```sh
maestro test .maestro/flows --format junit
```

## 1. What belongs in E2E

| E2E (Maestro) | Unit (Jest + RNTL) |
| --- | --- |
| Sign-in reaches the home screen | Form validation messages |
| Place an order end to end | Mapping of a 409 to a message |
| Deep link opens the right screen | Link allow-list parsing |
| Permissions dialogs, native integration | Hook caching, optimistic updates |

Rule of thumb: keep roughly 5 to 15 flows. A flow exists for a journey whose failure would hurt the
business, not for every screen.

## 2. Test IDs are part of the contract

```tsx
<Pressable testID="checkout-submit" accessibilityRole="button" onPress={submit}>
```

Naming: `<feature>-<element>` in kebab-case; list items add the id (`order-card-o-1`). Flows select by
`id:` (the `testID`); select by visible text only for text that is neither translated nor dynamic. Never
select by index or coordinates. IDs do not change without updating flows.

## 3. A flow

The sign-up journey, using the test IDs of the `SignupScreen` in `react-native-input-validation` and the
orders list from `react-native-code-structure`:

```yaml
# .maestro/subflows/launch-signed-out.yaml
appId: com.example.app
---
- launchApp:
    clearState: true              # no stored token: the app starts signed out
- extendedWaitUntil:
    visible:
      id: signup-email
    timeout: 10000
```

```yaml
# .maestro/flows/sign-up.yaml
appId: com.example.app
tags: [critical]
---
- runFlow: ../subflows/launch-signed-out.yaml
- tapOn:
    id: signup-email
- inputText: ${E2E_USER}
- tapOn:
    id: signup-password
- inputText: ${MAESTRO_E2E_PASSWORD}
- tapOn:
    id: signup-confirm-password
- inputText: ${MAESTRO_E2E_PASSWORD}
- tapOn:
    id: signup-submit
- assertVisible:
    id: orders-list
```

`E2E_USER` is an address the seeded test backend resets before each run (section 4), so the sign-up
succeeds every time. Other journeys (sign-in, place order) follow the same shape with their own screens' IDs.

Credentials come from the environment or CI secrets, never from the repo, and only for a dedicated, low-privilege
test account. A password passed with `-e E2E_PASSWORD=...` appears in the process list, shell history and CI logs,
so do not put one on the command line. Export it as `MAESTRO_E2E_PASSWORD` from the secret store and reference
`${MAESTRO_E2E_PASSWORD}` in the flow (Maestro exposes shell variables prefixed `MAESTRO_` to flows; confirm on your
pinned version, not verified here). Non-secret values such as `E2E_USER` may use `-e`.

## 4. Determinism

- Run against a dedicated test backend or a mocked server with **seeded, resettable data**.
- `clearState: true` at the start; no flow depends on another flow's leftovers.
- Wait for conditions (`assertVisible`, `extendedWaitUntil`), never fixed sleeps.
- Disable animations and onboarding tours via a launch argument in test builds.
- Quarantine a flaky flow by tag within one working day, then fix or delete it.

## 5. Running and reporting

```sh
# MAESTRO_E2E_PASSWORD is already exported from the secret store; it is not passed with -e
maestro test .maestro/flows --include-tags critical -e E2E_USER="$E2E_USER"
```

E2E is not a required PR check: device builds are slow and flakier than the `verify` gate. Run the critical
flows nightly and on demand (`workflow_dispatch`, e.g. before merging a change to a critical journey) on one
iOS and one Android target, and the full set nightly; this is the `e2e.yml` workflow in `react-native-ci`.
Upload JUnit reports and screenshots as CI artifacts.

## Do / Don't

- ✅ Assert on outcomes the user sees, at each major step.
- ✅ Share steps through `subflows/`.
- ✅ Keep flows short (under ~25 steps).
- ❌ Testing validation permutations or error mapping through the UI.
- ❌ `sleep`-style waits or reliance on live production data.
- ❌ Selecting by text that is translated or dynamic.
- ❌ One giant flow covering the whole app.

## Cross-references

- `react-native-unit-tests`: the faster home for edge cases.
- `react-native-code-structure`: where `testID`s are set (components, via props).
- `react-native-ci`: building the test binary and running Maestro in CI.
