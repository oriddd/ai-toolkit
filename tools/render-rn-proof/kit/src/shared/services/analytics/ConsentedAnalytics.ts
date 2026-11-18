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
