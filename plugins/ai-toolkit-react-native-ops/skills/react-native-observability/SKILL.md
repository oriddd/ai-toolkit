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
last_reviewed: 2026-11-03
---

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
{ "dependencies": { "@sentry/react-native": "<current>" } }
```

`<current>`: pin the latest stable `@sentry/react-native` release (same version as `react-native-error-handling`).

## 1. Sentry init, once, early

```ts
// shared/config/env.ts: build-time configuration, filled from app.config / EXPO_PUBLIC_* (all public)
export type AppEnv = {
  name: 'development' | 'staging' | 'production';
  apiBaseUrl: string;
  sentryDsn: string;
  appId: string;
  version: string;
  buildNumber: string;                        // a string even when numeric: Sentry's `dist` is a string
};

// shared/services/observability/initSentry.ts
export function initSentry(env: AppEnv) {
  Sentry.init({
    dsn: env.sentryDsn,                       // public identifier, see react-native-security
    environment: env.name,
    release: `${env.appId}@${env.version}+${env.buildNumber}`,
    dist: env.buildNumber,
    enabled: !__DEV__,
    sendDefaultPii: false,                    // no IP, cookies or user details attached automatically
    tracesSampleRate: env.name === 'production' ? 0.1 : 1.0,
    enableAutoPerformanceTracing: true,
    beforeSend: scrubEvent,                   // section 2
    beforeSendTransaction: scrubEvent,
    beforeBreadcrumb: scrubBreadcrumb,
  });
}
// App.tsx: initSentry(env) before render; export default Sentry.wrap(App);
```

## 2. PII scrubbing

Errors, transactions and breadcrumbs all leave the device, so all three are scrubbed:

```ts
const SENSITIVE_KEY = /pass|token|secret|auth|cookie|email|phone|address/i;
const EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/g;
const scrubText = (s: string) => s.replace(EMAIL, '[email]');
const stripQuery = (url: string) => url.split('?')[0] ?? url;   // query strings carry ids, tokens, emails
const redact = (data: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(data).map(([k, v]) => [
    k, SENSITIVE_KEY.test(k) ? '[redacted]' : typeof v === 'string' ? scrubText(stripQuery(v)) : v,
  ]));

function scrubEvent<E extends Sentry.Event>(event: E): E {
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

const scrubBreadcrumb = (crumb: Sentry.Breadcrumb): Sentry.Breadcrumb => ({
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
`useAnalytics().track(...)` from hooks or handlers, never in render. Respect consent: the provider no-ops
until consent is granted. Tests inject `FakeAnalytics` and assert `events` outcomes.

## 6. Performance

- Use Sentry's React Navigation integration for screen-load spans; add `Sentry.startSpan` only around
  business-critical operations (checkout submit), not everywhere.
- Watch app start time, slow and frozen frames, and JS thread stalls; set budgets and review them each release.
- Sample traces (0.1 to 0.2 in production) to control cost.

## 7. Release health and source maps

Upload source maps and native symbols on every release build (the Sentry Expo/RN plugin or
`sentry-cli` in `react-native-ci`) using the same `release` and `dist` as `Sentry.init`, otherwise stack
traces are unreadable. Track crash-free sessions/users per release and halt a staged rollout when they dip
below the agreed threshold.

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
