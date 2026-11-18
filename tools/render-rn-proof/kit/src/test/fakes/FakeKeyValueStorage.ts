import type { KeyValueStorage } from '@shared/services/storage/KeyValueStorage';

export class FakeKeyValueStorage implements KeyValueStorage {
  private readonly entries = new Map<string, string>();

  get(key: string) {
    return Promise.resolve(this.entries.get(key) ?? null);
  }

  set(key: string, value: string) {
    this.entries.set(key, value);
    return Promise.resolve();
  }
}
