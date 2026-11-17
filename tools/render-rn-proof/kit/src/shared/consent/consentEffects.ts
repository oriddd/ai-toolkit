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
