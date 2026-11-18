import { renderHook } from '@testing-library/react-native';
import { useServices } from './ServicesContext';

describe('useServices', () => {
  it('fails loudly outside a provider', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    await expect(renderHook(() => useServices())).rejects.toThrow('ServicesProvider missing');
  });
});
