import type { SecureStore } from '@shared/services/secure-storage/SecureStore';
export class FakeSecureStore implements SecureStore {
  private readonly m = new Map<string, string>();
  get(key: string) {
    return Promise.resolve(this.m.get(key) ?? null);
  }
  set(key: string, value: string) {
    this.m.set(key, value);
    return Promise.resolve();
  }
  remove(key: string) {
    this.m.delete(key);
    return Promise.resolve();
  }
}
