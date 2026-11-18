import { renderHook } from '@testing-library/react-native';
import { fakeServices, testProviders } from '../../../test/renderWithProviders';
import { useAnalytics } from './useAnalytics';

describe('useAnalytics', () => {
  it('returns the analytics of the services provider', async () => {
    const services = fakeServices();
    const { result } = await renderHook(() => useAnalytics(), { wrapper: testProviders(services) });
    expect(result.current).toBe(services.analytics);
  });
});
