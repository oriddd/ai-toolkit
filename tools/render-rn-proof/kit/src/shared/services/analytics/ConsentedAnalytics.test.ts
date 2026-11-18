import { FakeAnalytics } from '../../../test/fakes/FakeAnalytics';
import { FakeKeyValueStorage } from '../../../test/fakes/FakeKeyValueStorage';
import { createConsentStore } from '@shared/consent/consent';
import { createConsentedAnalytics } from './ConsentedAnalytics';

const event = { name: 'signup_completed', props: { method: 'email' } } as const;

describe('createConsentedAnalytics', () => {
  it('drops events until consent is granted, forwards after, stops after withdrawal', async () => {
    const inner = new FakeAnalytics();
    const consent = createConsentStore(new FakeKeyValueStorage());
    const analytics = createConsentedAnalytics(inner, consent);
    analytics.track(event);
    await consent.update({ analytics: true });
    analytics.track(event);
    await consent.update({ analytics: false });
    analytics.track(event);
    expect(inner.events).toEqual([event]);
  });

  it('sets a user id only with consent but always lets null through', async () => {
    const inner = new FakeAnalytics();
    const consent = createConsentStore(new FakeKeyValueStorage());
    const analytics = createConsentedAnalytics(inner, consent);
    analytics.setUserId('u-1');
    expect(inner.userId).toBeNull();
    await consent.update({ analytics: true });
    analytics.setUserId('u-1');
    expect(inner.userId).toBe('u-1');
    analytics.setUserId(null);
    expect(inner.userId).toBeNull();
  });
});
