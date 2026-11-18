export interface KeyValueStorage {
  get(key: string): Promise<string | null>;
  set(key: string, v: string): Promise<void>;
}
