import * as Application from 'expo-application';
// shared/config/appInfo.ts: version and build number come from the installed binary at runtime, never from
// EXPO_PUBLIC_*: EAS owns the build number remotely (react-native-ci §4) and shell variables never reach EAS cloud builds
export type AppInfo = { appId: string; version: string; buildNumber: string };
export const readAppInfo = (): AppInfo | null => {
  const { applicationId, nativeApplicationVersion, nativeBuildVersion } = Application; // expo-application
  return applicationId && nativeApplicationVersion && nativeBuildVersion
    ? { appId: applicationId, version: nativeApplicationVersion, buildNumber: nativeBuildVersion }
    : null; // web, or a host app such as Expo Go: let Sentry pick its defaults
};
