import { FakeKeyValueStorage } from '../../test/fakes/FakeKeyValueStorage';
import { createConsentStore } from './consent';
import { bindConsentEffects } from './consentEffects';

const setup = () => {
  const store = createConsentStore(new FakeKeyValueStorage());
  const push = { register: jest.fn(() => Promise.resolve()), unregister: jest.fn(() => Promise.resolve()) };
  const clearTelemetryIdentity = jest.fn();
  const onError = jest.fn();
  bindConsentEffects(store, { push, clearTelemetryIdentity, onError });
  return { store, push, clearTelemetryIdentity, onError };
};

describe('bindConsentEffects', () => {
  it('registers push on grant and unregisters on withdrawal', async () => {
    const { store, push } = setup();
    await store.update({ push: true });
    await store.update({ push: false });
    expect(push.register).toHaveBeenCalledTimes(1);
    expect(push.unregister).toHaveBeenCalledTimes(1);
  });

  it('does nothing for an unrelated change', async () => {
    const { store, push, clearTelemetryIdentity } = setup();
    await store.update({ analytics: true });
    expect(push.register).not.toHaveBeenCalled();
    expect(clearTelemetryIdentity).not.toHaveBeenCalled();
  });

  it.each([['analytics'], ['crashReports']] as const)('clears the telemetry identity when %s is withdrawn', async (key) => {
    const { store, clearTelemetryIdentity } = setup();
    await store.update({ [key]: true });
    await store.update({ [key]: false });
    expect(clearTelemetryIdentity).toHaveBeenCalledTimes(1);
  });

  it('reports a failed push registration', async () => {
    const { store, push, onError } = setup();
    const failure = new Error('no network');
    push.register.mockRejectedValueOnce(failure);
    await store.update({ push: true });
    await Promise.resolve();
    expect(onError).toHaveBeenCalledWith(failure);
  });
});
