import * as ExpoSecureStore from 'expo-secure-store';
export interface SecureStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}
export const createExpoSecureStore = (service: string): SecureStore => ({
  get: (key) => ExpoSecureStore.getItemAsync(`${service}.${key}`),
  set: (key, value) =>
    ExpoSecureStore.setItemAsync(`${service}.${key}`, value, {
      keychainAccessible: ExpoSecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
    }),
  remove: (key) => ExpoSecureStore.deleteItemAsync(`${service}.${key}`),
});
