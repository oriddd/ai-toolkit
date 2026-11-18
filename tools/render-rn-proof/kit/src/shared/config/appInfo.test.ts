import type { readAppInfo } from './appInfo';

describe('readAppInfo', () => {
  afterEach(() => {
    jest.resetModules();
    jest.dontMock('expo-application');
  });

  it('returns null where the binary reports nothing (web, Expo Go)', () => {
    jest.doMock('expo-application', () => ({
      applicationId: null,
      nativeApplicationVersion: null,
      nativeBuildVersion: null,
    }));
    const { readAppInfo: read } = jest.requireActual<{ readAppInfo: typeof readAppInfo }>('./appInfo');
    expect(read()).toBeNull();
  });

  it('reads id, version and build number from the installed binary', () => {
    jest.doMock('expo-application', () => ({
      applicationId: 'com.example.shop',
      nativeApplicationVersion: '1.2.3',
      nativeBuildVersion: '45',
    }));
    const { readAppInfo: read } = jest.requireActual<{ readAppInfo: typeof readAppInfo }>('./appInfo');
    expect(read()).toEqual({ appId: 'com.example.shop', version: '1.2.3', buildNumber: '45' });
  });
});
