import { FakeKeyValueStorage } from '../../test/fakes/FakeKeyValueStorage';
import { createConsentStore, NO_CONSENT } from './consent';

describe('createConsentStore', () => {
  it('denies by default', () => {
    expect(createConsentStore(new FakeKeyValueStorage()).current()).toEqual(NO_CONSENT);
  });

  it('persists a decision and restores it', async () => {
    const storage = new FakeKeyValueStorage();
    await createConsentStore(storage).update({ analytics: true });
    expect((await createConsentStore(storage).load()).analytics).toBe(true);
  });

  it.each(['not json', '{"analytics":"yes"}', '[]'])('falls back to no consent for %s', async (raw) => {
    const storage = new FakeKeyValueStorage();
    await storage.set('consent.v1', raw);
    expect(await createConsentStore(storage).load()).toEqual(NO_CONSENT);
  });

  it('notifies with the previous state and stops after unsubscribe', async () => {
    const store = createConsentStore(new FakeKeyValueStorage());
    const seen: boolean[] = [];
    const unsubscribe = store.subscribe((next, previous) => {
      seen.push(previous.push, next.push);
    });
    await store.update({ push: true });
    unsubscribe();
    await store.update({ push: false });
    expect(seen).toEqual([false, true]);
  });

  it('resets to no consent', async () => {
    const store = createConsentStore(new FakeKeyValueStorage());
    await store.update({ analytics: true, crashReports: true, push: true });
    await store.reset();
    expect(store.current()).toEqual(NO_CONSENT);
  });
});
