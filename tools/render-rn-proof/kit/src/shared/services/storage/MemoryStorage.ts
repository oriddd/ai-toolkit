import type { KeyValueStorage } from './KeyValueStorage';
export const createMemoryStorage = (): KeyValueStorage => {
  const m = new Map<string, string>();
  return {
    get: (k) => Promise.resolve(m.get(k) ?? null),
    set: (k, v) => {
      m.set(k, v);
      return Promise.resolve();
    },
  };
};
