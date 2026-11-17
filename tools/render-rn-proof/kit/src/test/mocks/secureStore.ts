const items = new Map<string, string>();

export const WHEN_UNLOCKED_THIS_DEVICE_ONLY = 'WHEN_UNLOCKED_THIS_DEVICE_ONLY';
export const getItemAsync = (key: string) => Promise.resolve(items.get(key) ?? null);
export const setItemAsync = (key: string, value: string) => {
  items.set(key, value);
  return Promise.resolve();
};
export const deleteItemAsync = (key: string) => {
  items.delete(key);
  return Promise.resolve();
};
