import { parseEnv } from './env';

const valid = { name: 'staging', apiBaseUrl: 'https://api.example.com', sentryDsn: '' };

describe('parseEnv', () => {
  it('accepts a valid build configuration', () => {
    expect(parseEnv(valid)).toEqual(valid);
  });

  it('rejects an http api url', () => {
    expect(() => parseEnv({ ...valid, apiBaseUrl: 'http://api.example.com' })).toThrow();
  });

  it('rejects a missing value', () => {
    expect(() => parseEnv({ ...valid, name: undefined })).toThrow();
  });
});
