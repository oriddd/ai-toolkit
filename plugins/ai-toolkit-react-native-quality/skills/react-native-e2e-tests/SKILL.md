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
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native E2E Tests Skill
## When to use

Use for a small set of **critical journeys** that need the real app on a simulator or device:
sign-in, purchase, onboarding, deep-link entry. Everything else is cheaper and more reliable as a unit test.

## Layout

```
.maestro/
├── flows/
│   ├── sign-up.yaml
│   ├── sign-in.yaml
│   └── deep-link-order.yaml
└── subflows/
    ├── launch-signed-out.yaml
    └── sign-in.yaml
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

Syntax needs no device: `maestro check-syntax .maestro/flows/sign-up.yaml` prints `OK` or the invalid command with its
line (checked with Maestro 2.12.1: the flows below pass, a misspelled `tapOnn` fails). Run it on every flow and subflow in the PR gate.
Record the pinned version in the repo (README) and in the CI image, then run:

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

## 3. Flows

The app id is the one `app.config.ts` gives the build under test. E2E builds use the `e2e` EAS profile of `react-native-ci`
§2, which sets `APP_VARIANT=production`: a simulator / emulator binary that is never uploaded, with bundle id and package
`com.example.shop` and the only variant that carries the verified links of the deep-link flow. Every flow starts
`appId: com.example.shop`.

A signed-out launch lands on `/sign-in` (the `RootNavigator` guard, `react-native-security` §1b), so every flow starts at
the sign-in screen, and a flow that needs a session signs in through the UI first. There is no session seed and no debug
backdoor in the app. The test IDs below are the ones of `SignInScreen` and `SignupScreen` in `react-native-input-validation`
(§4 and §8) and of the orders list and detail in `react-native-code-structure` (`orders-list`, `order-detail`):

```yaml
# .maestro/subflows/launch-signed-out.yaml
appId: com.example.shop
---
- launchApp:
    clearState: true              # app data and caches
    clearKeychain: true           # iOS: tokens live in the Keychain, which clearState leaves in place
- extendedWaitUntil:
    visible:
      id: signin-email            # what a signed-out launch shows
    timeout: 10000
```

```yaml
# .maestro/subflows/sign-in.yaml: runs on the sign-in screen
appId: com.example.shop
---
- tapOn:
    id: signin-email
- inputText: ${E2E_USER}
- tapOn:
    id: signin-password
- inputText: ${MAESTRO_E2E_PASSWORD}
- tapOn:
    id: signin-submit
- extendedWaitUntil:
    visible:
      id: orders-list
    timeout: 10000
```

```yaml
# .maestro/flows/sign-in.yaml
appId: com.example.shop
tags: [critical]
---
- runFlow: ../subflows/launch-signed-out.yaml
- runFlow: ../subflows/sign-in.yaml
```

```yaml
# .maestro/flows/sign-up.yaml
appId: com.example.shop
tags: [critical]
---
- runFlow: ../subflows/launch-signed-out.yaml
- tapOn:
    id: signin-create-account
- tapOn:
    id: signup-email
- inputText: ${E2E_NEW_USER}
- tapOn:
    id: signup-password
- inputText: ${MAESTRO_E2E_PASSWORD}
- tapOn:
    id: signup-confirm-password
- inputText: ${MAESTRO_E2E_PASSWORD}
- tapOn:
    id: signup-submit
- extendedWaitUntil:
    visible:
      id: signin-email            # a created account returns to sign-in
    timeout: 10000
- runFlow: ../subflows/sign-in.yaml    # the new account signs in
```

```yaml
# .maestro/flows/deep-link-order.yaml
appId: com.example.shop
tags: [critical]
---
- runFlow: ../subflows/launch-signed-out.yaml
- runFlow: ../subflows/sign-in.yaml
- openLink: https://evil.example.net/orders?orderId=${E2E_ORDER_ID}
- assertNotVisible:
    id: order-detail
- assertVisible:
    id: orders-list
- openLink: https://app.example.com/orders?orderId=${E2E_ORDER_ID}
- assertVisible:
    id: order-detail
```

The first link must leave the app where it is (`resolveDeepLink` allow-list, `react-native-security` section 3); the
second opens the detail of a seeded order. Verified-link setup, not the flow, decides whether the OS opens the app
(`react-native-security` `references/deep-link-server-setup.md`).

`E2E_USER` and `E2E_NEW_USER` are addresses the seeded test backend resets before each run (section 4): `E2E_USER` is a
seeded account, `E2E_NEW_USER` is free, so the sign-up succeeds every time. `E2E_ORDER_ID` is a seeded order of
`E2E_USER`. Place-order and other journeys follow the same shape with their own screens' IDs.

Credentials come from the environment or CI secrets, never from the repo, and only for a dedicated, low-privilege
test account. A password passed with `-e E2E_PASSWORD=...` appears in the process list, shell history and CI logs,
so do not put one on the command line. Export it as `MAESTRO_E2E_PASSWORD` from the secret store and reference
`${MAESTRO_E2E_PASSWORD}` in the flow (Maestro exposes shell variables prefixed `MAESTRO_` to flows; confirm on your
pinned version, not verified here). Non-secret values such as `E2E_USER` may use `-e`.

## 4. Determinism

- Run against a dedicated test backend or a mocked server with **seeded, resettable data**.
- `clearState: true` and `clearKeychain: true` at the start (the Keychain holds the tokens of `react-native-security`
  and survives `clearState` and even a reinstall on iOS; `clearKeychain` clears the whole simulator Keychain, so run iOS
  flows on a dedicated simulator); no flow depends on another flow's leftovers.
- Wait for conditions (`assertVisible`, `extendedWaitUntil`), never fixed sleeps.
- Disable animations and onboarding tours via a launch argument in test builds.
- Quarantine a flaky flow by tag within one working day, then fix or delete it.

## 5. Running and reporting

```sh
# MAESTRO_E2E_PASSWORD is already exported from the secret store; it is not passed with -e
maestro test .maestro/flows --include-tags critical -e E2E_USER="$E2E_USER" -e E2E_NEW_USER="$E2E_NEW_USER" -e E2E_ORDER_ID="$E2E_ORDER_ID"
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
