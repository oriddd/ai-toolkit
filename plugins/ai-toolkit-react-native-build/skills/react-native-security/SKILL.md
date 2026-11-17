---
name: react-native-security
description: >
  React Native security baseline — tokens in Keychain/Keystore, no secrets in the JS bundle, deep-link validation, TLS
  and pinning stance, PII-free logging. Use when storing credentials, handling deep links, adding config or keys, or
  adding logs.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-input-validation]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Security Skill
## When to use

Use when handling tokens or personal data, reading configuration, registering deep links or universal
links, calling remote APIs, or writing log statements. Assume the device and the JS bundle are hostile.

## Layout

```
shared/services/secure-storage/
├── SecureStore.ts            # interface: get/set/remove
├── KeychainSecureStore.ts    # Keychain (iOS) / Keystore (Android) implementation
└── FakeSecureStore.ts        # in-memory, for tests
shared/session/createAuthSession.ts   # AuthSession: access token + single-flight refresh
shared/session/signOut.ts
shared/services/logger/Logger.ts
features/links/model/linkSchemas.ts
```

## Dependencies

```json
{ "dependencies": { "react-native-keychain": "^11.0.0", "react-native-url-polyfill": "^4.0.0" } }
```

(Expo apps may use `expo-secure-store` behind the same interface, added with `npx expo install expo-secure-store` so it
matches the SDK.) `react-native-keychain` 11 peers on
React Native >= 0.82; an older app stays on the newest major that supports its React Native version.

## 1. Secure storage behind an interface

```ts
export interface SecureStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

export const createKeychainStore = (service: string): SecureStore => ({
  async get(key) { const r = await Keychain.getGenericPassword({ service: `${service}.${key}` }); return r ? r.password : null; },
  async set(key, value) { await Keychain.setGenericPassword(key, value, { service: `${service}.${key}`,
    accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY }); },
  async remove(key) { await Keychain.resetGenericPassword({ service: `${service}.${key}` }); },
});
```

Tokens, refresh tokens and keys go here. `AsyncStorage`/MMKV is plaintext: use it for preferences only.
Clear the store on sign-out and when a refresh fails, together with everything else that holds the previous
user's data, so the next user never sees it:

```ts
// shared/session/signOut.ts: the one sign-out path (sign-out button, failed refresh, 401)
export async function signOut(queryClient: QueryClient, secure: SecureStore): Promise<void> {
  await secure.remove('token');
  await secure.remove('refreshToken');
  queryClient.clear();                          // in-memory query and mutation caches
  useSessionStore.getState().signOut();         // every user-scoped Zustand store
  // persisted cache (react-query-persist-client): also `await persister.removeClient()`
}
```

### 1b. Token refresh: once, single-flight

The api-client (`react-native-state-and-data` §1) answers a 401 by calling `session.refresh()` once and retrying the
request once with the new token. The session makes concurrent 401s share **one** refresh call, keeps both tokens in
the `SecureStore`, and returns `null` only when the server rejects the refresh token:

```ts
// shared/session/createAuthSession.ts
const tokenPairSchema = z.object({ accessToken: z.string().min(1), refreshToken: z.string().min(1) });

// anonymousHttp: createHttpClient(baseUrl, anonymousSession), so the refresh call never recurses into a refresh
export function createAuthSession(secure: SecureStore, anonymousHttp: HttpClient): AuthSession {
  let inFlight: Promise<string | null> | null = null;

  const exchange = async (refreshToken: string) => {
    try {
      return await anonymousHttp.request({ path: '/auth/refresh', method: 'POST', body: { refreshToken } }, tokenPairSchema);
    } catch (e) {
      if (e instanceof UnauthorizedError || (isAppError(e) && e.code === 'BAD_REQUEST')) return null;  // session over
      throw e;                                   // offline or 5xx: the request fails retryably, the user stays signed in
    }
  };

  const refreshOnce = async (): Promise<string | null> => {
    const refreshToken = await secure.get('refreshToken');
    if (!refreshToken) return null;
    const pair = await exchange(refreshToken);
    if (!pair) return null;
    await secure.set('token', pair.accessToken);
    await secure.set('refreshToken', pair.refreshToken);   // rotated refresh tokens replace the old one
    return pair.accessToken;
  };

  return {
    getToken: () => secure.get('token'),
    refresh: () => {
      inFlight ??= refreshOnce().finally(() => { inFlight = null; });
      return inFlight;
    },
  };
}
```

`bootstrap/createServices.ts` builds it, and puts `secure` into `Services` so the sign-out path can reach it:

```ts
export const createServices = (env: AppEnv): Services => {
  const secure = createKeychainStore('app');
  const session = createAuthSession(secure, createHttpClient(env.apiUrl, anonymousSession));
  return { http: createHttpClient(env.apiUrl, session), secure, /* storage, consent, logger, errorReporter, analytics */ };
};
```

The remaining 401 is wired once, in `QueryProvider` (`react-native-state-and-data` §7): `createQueryClient({ errorReporter,
onUnauthorized })` calls `signOut(client, secure)` from the `QueryCache` / `MutationCache` `onError` when the error is an
`UnauthorizedError`, which now means "refresh failed", never "access token expired". `signOut` empties the session store, and
the root navigator reacts to that store, so no handler navigates by hand:

```tsx
// bootstrap/RootNavigator.tsx
export const RootNavigator = () => {
  const signedIn = useSessionStore((s) => s.userId !== null);
  return (
    <Stack>
      <Stack.Protected guard={signedIn}><Stack.Screen name="orders/index" /><Stack.Screen name="orders/[id]" /></Stack.Protected>
      <Stack.Protected guard={!signedIn}><Stack.Screen name="sign-in" /></Stack.Protected>
    </Stack>
  );
};
```

Proved with a jest test (`react-native-unit-tests` §3a): 401, one failed refresh call, tokens removed, cache cleared, router on
`/sign-in`; and the twin where the refresh works and the user stays.

## 2. No secrets in the bundle

Anything in `process.env.EXPO_PUBLIC_*`, `react-native-config` or source ships to every user and can
be extracted. Therefore:

- Never embed API secrets, signing keys or third-party private keys; call your backend, which holds them.
- Public identifiers (Sentry DSN, publishable keys) are acceptable; document each as intentionally public.
- Keep build secrets in the CI secret store (see `react-native-ci`), never in the repo or `.env` committed files.

## 3. Deep links and universal links

Treat every link as untrusted input: allow-list the routes and parse the params.

```ts
// First import of the app entry file: `src/app/_layout.tsx` in an Expo Router app (its entry, `expo-router/entry`,
// is not your file), or `index.js`/`index.ts` (React Native CLI, Expo without Expo Router).
// React Native's built-in URL throws "not implemented" on hostname, pathname and searchParams up to at
// least 0.79; the polyfill makes this code version-independent.
import 'react-native-url-polyfill/auto';

// features/links/model/linkSchemas.ts
export type Route = { name: 'OrderDetail'; params: { id: OrderId } };   // router-neutral target; OrderId from @features/orders
const orderLink = z.object({ orderId: z.uuid().brand<'OrderId'>() });   // same brand as orderSchema's id

const parseUrl = (url: string): URL | null => {
  try { return new URL(url); } catch { return null; }   // malformed links are untrusted input too
};

export function resolveDeepLink(url: string): Route | null {
  const u = parseUrl(url);
  if (!u || u.protocol !== 'https:' || u.hostname !== 'app.example.com') return null;
  if (u.pathname === '/orders') {
    const p = orderLink.safeParse(Object.fromEntries(u.searchParams));
    return p.success ? { name: 'OrderDetail', params: { id: p.data.orderId } } : null;
  }
  return null;
}
```

Minimum React Native: with `react-native-url-polyfill` installed there is no minimum for this code. Without it,
use only a React Native release whose `URL` implements these getters (not 0.79 or earlier) and unit-test
`resolveDeepLink` in the app's own test setup. Do not hand-parse links with regexes.

Wire it once, so every incoming URL goes through `resolveDeepLink` and a `null` result is ignored (the app stays where
it is). Expo Router opens any URL that matches a route file by itself, so intercept it in `src/app/+native-intent.tsx`:

```ts
// src/app/+native-intent.tsx: Expo Router calls this for the initial URL and every later one
export function redirectSystemPath({ path }: { path: string; initial: boolean }): string | null {
  const route = resolveDeepLink(path);                   // from @features/links
  return route ? `/orders/${encodeURIComponent(route.params.id)}` : null;
}
```

React Navigation apps pass the initial URL from `Linking.getInitialURL()` and later ones from
`Linking.addEventListener('url', ...)` (or `linking.getStateFromPath`) through it. Either way the screen still parses
its own route params (`react-native-code-structure` §4), because a link that maps to a route file is a route param. Test the mapping as a pure function (`react-native-unit-tests`)
and the entry as one Maestro flow (`react-native-e2e-tests`).

Prefer verified universal/app links over custom schemes: the server files, `app.config.ts` entries and the verification\ncommands are in [deep-link-server-setup.md](./references/deep-link-server-setup.md). Never navigate to a route or open a URL taken
from a link without the allow-list. Links never carry tokens or trigger a state-changing action without a confirm step.

## 4. Transport

- HTTPS only; no `usesCleartextTraffic` and no ATS exceptions in release builds.
- Certificate pinning is a deliberate decision, not a default: it protects high-risk apps (payments,
  health) but can brick the app on certificate rotation. If adopted, pin the public key with at least a
  backup pin and ship a remote kill-switch; otherwise rely on platform TLS.
- Authorization headers are added in the api-client only, never in feature code.

## 5. Logging without PII

```ts
export type LogContext = Record<string, string | number | boolean>;
export interface Logger {
  debug(msg: string, ctx?: LogContext): void;
  info(msg: string, ctx?: LogContext): void;
  warn(msg: string, ctx?: LogContext): void;
  error(msg: string, ctx?: LogContext): void;
}
// ✅ logger.info('order_cancelled', { orderId });
// ❌ logger.info(`user ${email} token ${token}`)
```

Never log tokens, passwords, emails, phone numbers, addresses or full request bodies. Log ids and
codes. Strip `console.log`/`info`/`debug` from release builds
(`['transform-remove-console', { exclude: ['error', 'warn'] }]` in `babel-plugin-transform-remove-console`;
Sentry turns `console.error`/`warn` into breadcrumbs) and redact fields in the Sentry `beforeSend` hook (see
`react-native-observability`). `no-console` stays an error everywhere except the one logger implementation
that writes to the console (a file-level override in `eslint.config.mjs`, see `react-native-static-analysis`).

## 6. Device and platform hygiene

- Disable Android backup of sensitive data (`allowBackup="false"` or exclusion rules).
- Hide sensitive screens in the app switcher (`FLAG_SECURE` / blur on inactive) where appropriate.
- Gate biometrics with `react-native-keychain` access control, not a JS boolean.
- Run `npm audit` (or an equivalent) in CI and pin native dependency versions.

## 7. Personal data, consent and deletion

Telemetry and push are opt-in when the app serves the EU: consent state gates Sentry, analytics and push registration, a
withdrawal takes effect at once, and the app offers an in-app account deletion request (an App Store requirement as well).
The code, the data-subject rules and the tests are in `react-native-observability`, `references/consent-and-data-deletion.md`.

## References

| Topic | Load when | File |
| --- | --- | --- |
| apple-app-site-association, `assetlinks.json`, `associatedDomains`, `intentFilters`, verification commands | registering a universal / app link or debugging one that opens the browser | [deep-link-server-setup.md](./references/deep-link-server-setup.md) |
| Consent gating, data-subject deletion (observability skill) | the app collects analytics, crashes or push tokens, or a user can delete an account | `react-native-observability` references |

## Do / Don't

- ✅ Inject `SecureStore` and `Logger`; use fakes in tests.
- ✅ One refresh for any number of concurrent 401s; retry each request once, then sign out.
- ✅ Validate and allow-list every deep link.
- ✅ Treat every value in the JS bundle as public.
- ❌ Tokens or refresh tokens in `AsyncStorage`, Redux persist or Zustand `persist` without a secure engine.
- ❌ Signing out on the first 401, or refreshing per request without single-flight.
- ❌ `console.log` of request, response or user objects.
- ❌ Disabling TLS verification, even in debug flavours committed to the repo.
- ❌ Trusting `Linking.getInitialURL()` params as typed data.

## Cross-references

- `react-native-input-validation`: schemas used for link parameters.
- `react-native-observability`: PII scrubbing in crash reports and analytics.
- `react-native-ci`: secret handling in pipelines.
- `react-native-error-handling`: `UnauthorizedError` triggers store clearing.
