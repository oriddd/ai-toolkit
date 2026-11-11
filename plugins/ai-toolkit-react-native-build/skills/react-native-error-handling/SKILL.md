---
name: react-native-error-handling
description: >
  React Native error contract — typed AppError hierarchy, message catalogue, API-error mapping in one place, error
  boundaries, reporting hook. Use when throwing, mapping, displaying or reporting any failure. For input rules use
  `react-native-input-validation`.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-state-and-data]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Error Handling Skill
## When to use

Use when code can fail (network, parsing, storage, permissions) or when a failure must reach the
user or the crash reporter. Failures are typed values with stable codes; user-facing text comes
from one catalogue; HTTP and transport details are translated in one place.

## Layout

```
shared/errors/
├── AppError.ts          # base class + subclasses
├── errorMessages.ts     # code -> user-facing message (the catalogue)
├── mapHttpError.ts      # the ONLY place status codes become AppErrors
├── reportError.ts       # ErrorReporter interface + hook
└── ErrorBoundary.tsx
```

## Dependencies

```json
{ "dependencies": { "react-error-boundary": "^6.0.0", "@sentry/react-native": "<current>" } }
```

`<current>`: pin the latest stable `@sentry/react-native` release (same version as `react-native-observability`).
`react-error-boundary` 6 types `FallbackProps.error` and the `onError` error as `unknown`: narrow before use.

## 1. Typed hierarchy

```ts
// shared/errors/AppError.ts
export type ErrorCode =
  | 'NETWORK_OFFLINE' | 'UNAUTHORIZED' | 'FORBIDDEN' | 'NOT_FOUND' | 'CONFLICT' | 'VALIDATION_FAILED'
  | 'BAD_REQUEST' | 'RATE_LIMITED' | 'SERVER' | 'UNKNOWN';

export class AppError extends Error {
  constructor(readonly code: ErrorCode, readonly retryable: boolean, options?: { cause?: unknown }) {
    super(code, options);
    this.name = new.target.name;
  }
}
export class NetworkError extends AppError { constructor(cause?: unknown) { super('NETWORK_OFFLINE', true, { cause }); } }
export class UnauthorizedError extends AppError { constructor() { super('UNAUTHORIZED', false); } }
export class NotFoundError extends AppError { constructor() { super('NOT_FOUND', false); } }
export class ServerError extends AppError { constructor(readonly status: number) { super('SERVER', true); } }
export type FieldErrors = Record<string, string>;        // form field path -> server error code
export class ValidationError extends AppError { constructor(readonly fieldErrors: FieldErrors) { super('VALIDATION_FAILED', false); } }
export const isAppError = (e: unknown): e is AppError => e instanceof AppError;
```

Add a subclass only when callers branch on it; otherwise a new `ErrorCode` is enough. Every 4xx the API documents gets its own code, so nothing expected lands in `UNKNOWN` and is reported as a bug.

## 2. Message catalogue

```ts
// shared/errors/errorMessages.ts
export const errorMessages: Record<ErrorCode, string> = {
  NETWORK_OFFLINE: "You're offline. Check your connection and try again.",
  UNAUTHORIZED: 'Your session expired. Please sign in again.',
  FORBIDDEN: "You don't have permission to do that.",
  NOT_FOUND: "We couldn't find what you were looking for.",
  CONFLICT: 'This item was changed elsewhere. Refresh and retry.',
  VALIDATION_FAILED: 'Some of the information is not valid.',
  BAD_REQUEST: 'We could not process that request. Please try again.',
  RATE_LIMITED: 'Too many requests. Please wait a moment and try again.',
  SERVER: 'Something went wrong on our side. Please try again.',
  UNKNOWN: 'Something went wrong. Please try again.',
};
export const messageFor = (e: unknown): string => errorMessages[isAppError(e) ? e.code : 'UNKNOWN'];
```

`Record<ErrorCode, string>` makes a missing message a compile error. Messages never contain
server text, stack traces or ids. When localising, key this by `ErrorCode` into your i18n bundle.

## 3. One mapping point

```ts
// shared/errors/mapHttpError.ts
export async function mapHttpError(res: Response): Promise<AppError> {
  switch (res.status) {
    case 400: return new AppError('BAD_REQUEST', false);
    case 401: return new UnauthorizedError();
    case 403: return new AppError('FORBIDDEN', false);
    case 404: return new NotFoundError();
    case 409: return new AppError('CONFLICT', false);
    case 422: return new ValidationError(await readFieldErrors(res));
    case 429: return new AppError('RATE_LIMITED', false);
    default:  return res.status >= 500 ? new ServerError(res.status) : new AppError('UNKNOWN', false);
  }
}
export const toNetworkError = (cause: unknown) => new NetworkError(cause);
// a response that breaks the zod contract is our bug: UNKNOWN is reported and not retried
export const toContractError = (cause: unknown) => new AppError('UNKNOWN', false, { cause });

// 422 bodies are problem+json with `errors: [{ field, code, message }]` (see python-error-handling / exception-handling)
const problemSchema = z.object({ errors: z.array(z.object({ field: z.string(), code: z.string() })).default([]) });
async function readFieldErrors(res: Response): Promise<FieldErrors> {
  const parsed = problemSchema.safeParse(await res.json().catch(() => null));
  if (!parsed.success) return {};
  return Object.fromEntries(parsed.data.errors.map((e) => [e.field.replace(/^body\./, ''), e.code]));  // `body.email` -> `email`
}
```

Only the codes are kept, never the server's message text: the form maps each code to the validation catalogue
(see `react-native-input-validation`).

Only the api-client (see `react-native-state-and-data`) calls this. No `if (status === 401)` in
screens, hooks or feature api modules.

## 4. Showing errors

```tsx
export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const retryable = isAppError(error) && error.retryable;
  return (
    <View accessibilityRole="alert" testID="error-state">
      <Text>{messageFor(error)}</Text>
      {retryable && onRetry ? <Button title="Try again" onPress={onRetry} /> : null}
    </View>
  );
}
```

Inline errors for queries; toast/banner for mutations; never `Alert.alert(error.message)`.

## 5. Error boundaries

Boundaries catch **render** errors only; async errors flow through query/mutation state.

```tsx
// CrashScreen is the app's own full-screen "something went wrong" view with a restart button.
// hoisted: an inline arrow is a new component type every render and would remount the fallback
const CrashFallback = ({ resetErrorBoundary }: FallbackProps) => <CrashScreen onRestart={resetErrorBoundary} />;

export const AppErrorBoundary = ({ children }: PropsWithChildren) => {
  const reporter = useErrorReporter();
  return (
    <ErrorBoundary
      onError={(error, info) => reporter.report(error, { componentStack: info.componentStack })}
      FallbackComponent={CrashFallback}>
      {children}
    </ErrorBoundary>
  );
};
```

One boundary at the app root, plus one per navigator or risky widget so a failure stays contained.

## 6. Reporting hook

```ts
// shared/errors/reportError.ts
export interface ErrorReporter { report(error: unknown, context?: Record<string, unknown>): void; }
export const useErrorReporter = (): ErrorReporter => useServices().errorReporter; // useServices: @shared/services/ServicesContext

const REPORTED: ReadonlySet<ErrorCode> = new Set(['UNKNOWN', 'SERVER', 'BAD_REQUEST']);
export const isReportable = (e: unknown): boolean => !isAppError(e) || REPORTED.has(e.code);
```

`shared/errors` imports `useServices` from `shared/services`, and `ServicesContext.tsx` imports the
`ErrorReporter` type back. Keep that second import `import type { ErrorReporter }`: it is erased at
compile time, so there is no runtime import cycle (`consistent-type-imports` in `react-native-static-analysis`
enforces the form).

The Sentry implementation lives behind this interface (see `react-native-observability`). Report
unexpected errors (`UNKNOWN`, `SERVER`, `BAD_REQUEST` because our own client sent it, render crashes); do not
report expected ones such as `NETWORK_OFFLINE`, `UNAUTHORIZED`, `FORBIDDEN`, `RATE_LIMITED` or `VALIDATION_FAILED`
(`isReportable` above). Wire it once in the `QueryCache` / `MutationCache` `onError` of the `QueryClient` that
`QueryProvider` creates inside the services provider (see `react-native-state-and-data` §7), not per call.

## Do / Don't

- ✅ Throw `AppError` subclasses; keep the original as `cause`.
- ✅ Add a catalogue entry in the same change as a new `ErrorCode`.
- ✅ Make `retryable` drive retry UI and query retry policy.
- ❌ `catch (e) { console.log(e) }` or an empty catch.
- ❌ `throw new Error('failed')` or `throw 'string'`.
- ❌ Showing `error.message` from the server to the user.
- ❌ Status-code checks outside `mapHttpError`.

## Cross-references

- `react-native-state-and-data`: api-client calls `mapHttpError`; query retry uses `retryable`.
- `react-native-input-validation`: field errors are validation results, not `AppError`s thrown to the boundary.
- `react-native-observability`: the Sentry `ErrorReporter` implementation.
- `react-native-unit-tests`: test the mapper table and the catalogue's completeness.
