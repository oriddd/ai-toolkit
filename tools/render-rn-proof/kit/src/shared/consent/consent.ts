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
