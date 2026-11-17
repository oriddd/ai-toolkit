import * as ExpoSecureStore from 'expo-secure-store';
import { createExpoSecureStore } from './SecureStore';

describe('createExpoSecureStore', () => {
  it('stores, reads and removes a value under a namespaced key', async () => {
    const store = createExpoSecureStore('app');
    await store.set('token', 'abc');
    expect(await store.get('token')).toBe('abc');
    expect(await ExpoSecureStore.getItemAsync('app.token')).toBe('abc');
    await store.remove('token');
    expect(await store.get('token')).toBeNull();
  });
});
