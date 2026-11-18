---
name: react-native-observability
description: >
  React Native observability — Sentry crash and performance monitoring, structured logging, analytics behind an
  interface, PII scrubbing, release health. Use when adding crash reporting, events, logging or tracing, or when
  production issues cannot be diagnosed.
tier: should
applies_to: [mobile]
depends_on: [react-native-error-handling, react-native-security, react-native-ci]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Observability Skill
## When to use

Use when you need to know what the app does in the field: crashes, slow screens, funnel events,
and structured logs. Vendors (Sentry, an analytics SDK) sit behind interfaces so they are swappable and
fakeable, and feature code never imports an SDK directly.

## Layout

```
shared/services/
├── observability/
│   ├── initSentry.ts          # the only file that calls Sentry.init
│   ├── scrubPii.ts            # scrubEvent / scrubBreadcrumb, exported and unit-tested
│   └── SentryErrorReporter.ts # implements ErrorReporter
├── logger/Logger.ts  ConsoleLogger.ts  SentryBreadcrumbLogger.ts
└── analytics/
    ├── Analytics.ts           # interface
    ├── events.ts              # typed event catalogue
    └── ProviderAnalytics.ts   # one vendor implementation
test/fakes/FakeAnalytics.ts
```

## Dependencies

```json
{ "dependencies": { "@sentry/react-native": "<current>", "expo-application": "<sdk-matched>" } }
```

`<current>`: in an Expo app, `npx expo install @sentry/react-native` (the version the SDK is built against, SDK 58:
`~8.28.0`); in a bare app, the latest stable release. Same version as `react-native-error-handling`.

## 1. Sentry init, once, early

```ts
// shared/config/env.ts: build-time configuration, all public (react-native-security §2), parsed once at startup
const appEnvSchema = z.object({
  name: z.enum(['development', 'staging', 'production']),
  apiBaseUrl: z.url({ protocol: /^https$/ }),
  sentryDsn: z.string(),
});
export type AppEnv = z.infer<typeof appEnvSchema>;
export const parseEnv = (raw: unknown): AppEnv => appEnvSchema.parse(raw);   // a bad build fails at launch, loudly

// bootstrap/env.ts: Expo inlines each `process.env.EXPO_PUBLIC_*` at build time, so write every reference out in full
// (no destructuring, no `process.env[name]`); tests call parseEnv directly
export const env = parseEnv({ name: process.env.EXPO_PUBLIC_APP_ENV, apiBaseUrl: process.env.EXPO_PUBLIC_API_BASE_URL,
  sentryDsn: process.env.EXPO_PUBLIC_SENTRY_DSN ?? '' });

// shared/config/appInfo.ts: version and build number come from the installed binary at runtime, never from
// EXPO_PUBLIC_*: EAS owns the build number remotely (react-native-ci §4) and shell variables never reach EAS cloud builds
export type AppInfo = { appId: string; version: string; buildNumber: string };
export const readAppInfo = (): AppInfo | null => {
  const { applicationId, nativeApplicationVersion, nativeBuildVersion } = Application;   // expo-application
  return applicationId && nativeApplicationVersion && nativeBuildVersion
    ? { appId: applicationId, version: nativeApplicationVersion, buildNumber: nativeBuildVersion }
    : null;                                      // web, or a host app such as Expo Go: let Sentry pick its defaults
};
```

Expo types `process.env` with an `any` index signature, so each read fails `no-unsafe-assignment`. Declare the
variables once in `shared/config/processEnv.d.ts`:
`declare global { namespace NodeJS { interface ProcessEnv { EXPO_PUBLIC_API_BASE_URL?: string; /* one per variable */ } } } export {};`

```ts
// shared/services/observability/initSentry.ts
export const navigationIntegration = Sentry.reactNavigationIntegration();   // screen-load spans, section 6

export function initSentry(env: AppEnv, app: AppInfo | null, crashReportsAllowed: () => boolean) {
  Sentry.init({
    dsn: env.sentryDsn,                       // public identifier, see react-native-security
    environment: env.name,
    ...(app && { release: `${app.appId}@${app.version}+${app.buildNumber}`, dist: app.buildNumber }),
    enabled: !__DEV__,
    tracesSampleRate: env.name === 'production' ? 0.1 : 1.0,
    enableAutoPerformanceTracing: true,
    integrations: [navigationIntegration],
    beforeSend: (event) => (crashReportsAllowed() ? scrubEvent(event) : null),     // scrub (section 2), and drop without consent
    beforeSendTransaction: (event) => (crashReportsAllowed() ? scrubEvent(event) : null),
    beforeBreadcrumb: (crumb) => (crashReportsAllowed() ? scrubBreadcrumb(crumb) : null),
  });
}
```

```tsx
// src/app/_layout.tsx (Expo Router): init at module load, register the router's navigation container once
initSentry(env, readAppInfo(), () => consent.current().crashReports);   // consent loaded first, see references/consent-and-data-deletion.md
function RootLayout() {
  const navigationRef = useNavigationContainerRef();     // expo-router
  useEffect(() => { navigationIntegration.registerNavigationContainer(navigationRef); }, [navigationRef]);
  return <AppProviders env={env}><Stack /></AppProviders>;
}
export default Sentry.wrap(RootLayout);
```

React Navigation apps call `initSentry` in `App.tsx`, export `Sentry.wrap(App)`, and register the ref in
`<NavigationContainer ref={navigationRef} onReady={() => { navigationIntegration.registerNavigationContainer(navigationRef); }}>`.
The release string is the one the Sentry Expo plugin and `sentry-cli` upload source maps for
(`<applicationId>@<version>+<buildNumber>`, `dist` = build number), so stack traces resolve (section 7).

`sendDefaultPii` is deliberately not set: `false` is the default (no IP, cookies or user details attached automatically),
and on `@sentry/react-native` ~8.28 (Expo SDK 58) writing it fails `no-deprecated` through a typings bug (fixed in 8.34).
Never set it to `true`. The snippet above is the one rendered into a SDK 58 app: `tsc`, `eslint --max-warnings 0`,
`prettier --check` and its jest test pass.

## 2. PII scrubbing

Errors, transactions and breadcrumbs all leave the device, so all three are scrubbed. The scrubbers live in
`scrubPii.ts`, exported, so `react-native-unit-tests` can prove each rule:

```ts
// shared/services/observability/scrubPii.ts
const SENSITIVE_KEY = /pass|token|secret|auth|cookie|email|phone|address/i;
const EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/g;
const scrubText = (s: string) => s.replace(EMAIL, '[email]');
const stripQuery = (url: string) => url.split('?')[0] ?? url;   // query strings carry ids, tokens, emails
const redact = (data: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(data).map(([k, v]) => [
    k, SENSITIVE_KEY.test(k) ? '[redacted]' : typeof v === 'string' ? scrubText(stripQuery(v)) : v,
  ]));

export function scrubEvent<E extends Sentry.Event>(event: E): E {
  if (event.user) event.user = event.user.id === undefined ? {} : { id: event.user.id };  // opaque id only
  if (event.request)
    event.request = {                                   // no headers, cookies, body or query string
      ...(event.request.url && { url: stripQuery(event.request.url) }),
      ...(event.request.method && { method: event.request.method }),
    };
  if (event.extra) event.extra = redact(event.extra);
  if (event.message) event.message = scrubText(event.message);
  for (const ex of event.exception?.values ?? []) if (ex.value) ex.value = scrubText(ex.value);
  return event;
}

export const scrubBreadcrumb = (crumb: Sentry.Breadcrumb): Sentry.Breadcrumb => ({
  ...crumb,
  ...(crumb.message && { message: scrubText(crumb.message) }),
  ...(crumb.data && { data: redact(crumb.data) }),      // http breadcrumbs carry the URL in data.url
});
```

The patterns are a safety net, not the rule: the rule is to never put PII into errors, logs or events.
Identify users by an opaque id only (`Sentry.setUser({ id })`). Same rules as logging in `react-native-security`.

## 3. ErrorReporter implementation

```ts
export const createSentryErrorReporter = (): ErrorReporter => ({
  report: (error, context) =>
    Sentry.captureException(error, {
      ...(context && { extra: context }),                       // conditional spread: exactOptionalPropertyTypes
      ...(isAppError(error) && { tags: { code: error.code } }), // forbids passing `undefined` for an optional key
    }),
});
```

This fulfils the `ErrorReporter` interface from `react-native-error-handling`, and is injected through the
services provider (`useServices` in `shared/services/`). Tag by `code`, so issues group by failure class, not message text.

## 4. Structured logging

```ts
import type * as Sentry from '@sentry/react-native'; // type-only: the logger never imports the SDK at runtime
export const createLogger = (sink: Pick<typeof Sentry, 'addBreadcrumb'>): Logger => ({
  info: (message, ctx) => sink.addBreadcrumb({ level: 'info', message, ...(ctx && { data: ctx }) }),
  error: (message, ctx) => sink.addBreadcrumb({ level: 'error', message, ...(ctx && { data: ctx }) }),
  /* debug / warn likewise */
});
```

Log events with a stable `snake_case` name plus a flat context object (`logger.info('order_cancelled', { orderId })`),
not interpolated sentences. Breadcrumbs give crash reports a trail. No PII; no raw request bodies.

## 5. Analytics behind an interface

```ts
// shared/services/analytics/events.ts
export type AnalyticsEvent =
  | { name: 'order_placed'; props: { orderId: string; itemCount: number } }   // pass order.id: a branded OrderId is a string
  | { name: 'signup_completed'; props: { method: 'email' | 'apple' } };

export interface Analytics { track(event: AnalyticsEvent): void; setUserId(id: string | null): void; }

// shared/services/analytics/useAnalytics.ts: `analytics` is part of `Services` (react-native-code-structure §6)
export const useAnalytics = (): Analytics => useServices().analytics;
```

The catalogue lives in `shared/`, which cannot import feature types such as `OrderId`, so ids are typed
`string` here.

Events are a typed union, so names and properties are compile-checked and reviewable in one file. Call
`useAnalytics().track(...)` from hooks or handlers, never in render. Respect consent: the provider is wrapped in `createConsentedAnalytics`, which no-ops until consent is granted
(`references/consent-and-data-deletion.md`). Tests inject `FakeAnalytics` and assert `events` outcomes.

## 6. Performance

- Screen-load spans come from `navigationIntegration` (section 1), registered with the router's navigation container;
  add `Sentry.startSpan` only around business-critical operations (checkout submit), not everywhere.
- Watch app start time, slow and frozen frames, and JS thread stalls; set budgets and review them each release.
- Sample traces (0.1 to 0.2 in production) to control cost.

## 7. Release health and source maps

Upload source maps and native symbols on every release build (the Sentry Expo/RN plugin or
`sentry-cli` in `react-native-ci`) using the same `release` and `dist` as `Sentry.init`, otherwise stack
traces are unreadable. Track crash-free sessions/users per release and halt a staged rollout when they dip
below the agreed threshold.

## 8. Consent and data deletion

Consent state gates Sentry, analytics and push registration, a withdrawal takes effect at once, and the app offers an in-app
account deletion request. Code, rules and tests: `references/consent-and-data-deletion.md`.

## References

| Topic | Load when | File |
| --- | --- | --- |
| Consent store, gating Sentry / analytics / push, account deletion flow, data-subject rules | the app serves EU or California users, collects analytics or push tokens, or has accounts | [consent-and-data-deletion.md](./references/consent-and-data-deletion.md) |

## Do / Don't

- ✅ Initialise once; wrap the root with `Sentry.wrap`.
- ✅ Typed events, flat log context, opaque user ids.
- ✅ Report only unexpected errors.
- ❌ Importing `@sentry/react-native` or an analytics SDK in a component.
- ❌ Logging tokens, emails or request bodies; tracking before consent.
- ❌ Free-form event name strings at call sites.
- ❌ Shipping a release without uploaded source maps.

## Cross-references

- `react-native-error-handling`: `ErrorReporter` interface and what to report.
- `react-native-security`: PII and logging rules.
- `react-native-ci`: source map upload, versions and rollouts.
- `react-native-unit-tests`: fakes for analytics and reporters.
