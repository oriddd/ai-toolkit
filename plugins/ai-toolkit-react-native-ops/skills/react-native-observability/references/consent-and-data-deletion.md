# Consent, personal data and account deletion

Beyond scrubbing (SKILL.md section 2), an app that serves people in the EU (GDPR) or California must let users decide
what leaves the device and must delete their data on request. The rules below are the engineering side; the legal basis
per data category is a product and legal decision.

## 1. What is gated

| Data | Default | Gate |
| --- | --- | --- |
| Analytics events and the analytics user id | off until granted | `createConsentedAnalytics` |
| Crash reports, traces, breadcrumbs (Sentry) | off until granted, or on as "legitimate interest" if legal agrees | `crashReportsAllowed` passed to `initSentry` |
| Push token registered with your backend | off until granted | `bindConsentEffects` registers / unregisters |
| Tokens, order data the user asked for | not consent: needed to run the app | none |

No consent decision means **no consent**. The state is stored in plain preferences (it is not a secret) and is read
once at launch (`await consent.load()` before `initSentry`); a corrupt value falls back to "none". A withdrawal applies
immediately, in memory first, so nothing is sent between the tap and the disk write.

## 2. Consent state

```ts
import { z } from 'zod';
import type { KeyValueStorage } from '@shared/services/storage/KeyValueStorage';

export const consentSchema = z.object({
  analytics: z.boolean(),
  crashReports: z.boolean(),
  push: z.boolean(),
});
export type Consent = z.infer<typeof consentSchema>;

export const NO_CONSENT: Consent = { analytics: false, crashReports: false, push: false };
const STORAGE_KEY = 'consent.v1';

export type ConsentListener = (next: Consent, previous: Consent) => void;

export interface ConsentStore {
  current(): Consent;
  load(): Promise<Consent>;
  update(patch: Partial<Consent>): Promise<void>;
  reset(): Promise<void>;
  subscribe(listener: ConsentListener): () => void;
}

const parseStored = (raw: string | null): Consent => {
  if (raw === null) return NO_CONSENT;
  try {
    return consentSchema.parse(JSON.parse(raw));
  } catch {
    return NO_CONSENT;
  }
};

export const createConsentStore = (storage: KeyValueStorage): ConsentStore => {
  let state = NO_CONSENT;
  const listeners = new Set<ConsentListener>();

  const commit = async (next: Consent) => {
    const previous = state;
    state = next;
    listeners.forEach((listener) => {
      listener(next, previous);
    });
    await storage.set(STORAGE_KEY, JSON.stringify(next));
  };

  return {
    current: () => state,
    load: async () => {
      state = parseStored(await storage.get(STORAGE_KEY));
      return state;
    },
    update: (patch) => commit({ ...state, ...patch }),
    reset: () => commit(NO_CONSENT),
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
};
```

`Services` carries `consent: ConsentStore` (`react-native-code-structure` section 6). A consent screen calls
`consent.update({ analytics: true })`; a settings screen offers the same switches again, because withdrawing must be as
easy as granting.

## 3. Gating each sink

Analytics wraps the vendor adapter, so feature code stays unaware (the `Analytics` interface is section 5 of SKILL.md):

```ts
import type { ConsentStore } from '@shared/consent/consent';
import type { Analytics } from './events';

export const createConsentedAnalytics = (inner: Analytics, consent: ConsentStore): Analytics => ({
  track: (event) => {
    if (consent.current().analytics) inner.track(event);
  },
  setUserId: (id) => {
    if (id === null || consent.current().analytics) inner.setUserId(id);
  },
});
```

`setUserId(null)` always passes, so a withdrawal can forget the identity. Sentry gets the same predicate in
`initSentry` (SKILL.md section 1): its three hooks return `null`, which discards the payload, while it is `false`. Pass
`() => true` where crash reports are treated as legitimate interest, or `() => consent.current().crashReports` where they
need consent. Push registration and the telemetry identity follow consent changes through one subscription:

```ts
import type { ConsentStore } from './consent';

export interface PushRegistration {
  register(): Promise<void>;
  unregister(): Promise<void>;
}

export type ConsentEffects = {
  push: PushRegistration;
  clearTelemetryIdentity: () => void;
  onError: (error: unknown) => void;
};

export const bindConsentEffects = (consent: ConsentStore, effects: ConsentEffects) =>
  consent.subscribe((next, previous) => {
    if (next.push !== previous.push) {
      const change = next.push ? effects.push.register() : effects.push.unregister();
      change.catch(effects.onError);
    }
    const lostTelemetry =
      (previous.analytics && !next.analytics) || (previous.crashReports && !next.crashReports);
    if (lostTelemetry) effects.clearTelemetryIdentity();
  });
```

Bind it once at start-up, with `clearTelemetryIdentity: () => { Sentry.setUser(null); analytics.setUserId(null); }` and
`onError: (e) => { errorReporter.report(e); }`. `push` is the `registerForPush` flow of `react-native-permissions-and-push`
plus `devicesApi.unregister` for the backend row; the OS permission itself stays a separate decision from this consent.

## 4. Deleting a user's data

A user can ask for deletion inside the app (the App Store requires it for apps that create accounts). The app does three
things: asks the backend, and only when the backend accepted, erases everything local and signs out. A failed request
changes nothing locally, so the user can retry and no data is orphaned.

```ts
import { z } from 'zod';

export const deletionReceiptSchema = z.object({ requestId: z.string().min(1) });
export type DeletionReceipt = z.infer<typeof deletionReceiptSchema>;

import type { HttpClient } from '@shared/api-client/httpClient';
import { deletionReceiptSchema, type DeletionReceipt } from '../model/deletionSchemas';

export const createAccountApi = (http: HttpClient) => ({
  requestDeletion: (): Promise<DeletionReceipt> =>
    http.request({ path: '/me', method: 'DELETE' }, deletionReceiptSchema),
});
```

```ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { signOut } from '@shared/session/signOut';
import { useServices } from '@shared/services/ServicesContext';
import { useAccountApi } from './useAccountApi';

export function useDeleteAccount() {
  const queryClient = useQueryClient();
  const { secure, consent } = useServices();
  const accountApi = useAccountApi();
  return useMutation({
    mutationFn: accountApi.requestDeletion,
    onSuccess: async () => {
      await signOut(queryClient, secure);
      await consent.reset();
    },
  });
}
```

The endpoint returns `202` with a receipt: the backend erases or anonymises asynchronously (database, backups on their
retention schedule, analytics and crash vendors via their deletion APIs) and the receipt id is what support quotes.
Show a confirmation step before calling the hook (destructive, irreversible) and, afterwards, the receipt id and the
signed-out screen. `signOut` clears tokens, the query and mutation caches and the session store
(`react-native-security` section 1); also call `persister.removeClient()` if the query cache is persisted, and clear
any other local store the app owns.

## 5. Data-subject rules for the rest of the app

- Collect the minimum: an event or log field that no one reads is not collected.
- Identify people by an opaque id in telemetry (`Sentry.setUser({ id })`), never an email or phone number.
- Keep PII out of query keys, route params, log context and screen names; they end up in breadcrumbs.
- Name every SDK that sends data in the privacy policy, and keep the iOS privacy manifest and the store data-safety forms
  in step with it (`react-native-app-config-and-updates`, `references/ios-privacy-manifest.md`).
- Exporting a user's data (access request) is a backend endpoint behind the same authenticated call; the app only links to it.

## 6. Tests

All passing under `npm run verify` in the proof app:

- `createConsentStore`: denies by default, persists and notifies with the previous state, restores a saved decision, falls
  back to none for `not json`, `{"analytics":"yes"}` and `[]`, stops notifying after unsubscribe.
- `bindConsentEffects`: push registers on grant and unregisters on withdrawal, no call for unrelated changes, identity cleared
  when analytics or crash reports are withdrawn, a failed registration reaches `onError`.
- `createConsentedAnalytics`: drops events until granted, forwards after, stops after withdrawal, always lets `setUserId(null)` through.
- `initSentry` with the `@sentry/react-native` mock (`react-native-unit-tests` section 4): `beforeSend` returns `null` while not
  allowed and a scrubbed event when allowed; `beforeBreadcrumb` and `beforeSendTransaction` return `null` while not allowed.
- `useDeleteAccount` with MSW: a `202` signs out, removes the tokens, clears the cache and withdraws every consent; a `500`
  leaves the session, tokens, cache and consent untouched and rejects with the `SERVER` error.
