import type { ConfigContext, ExpoConfig } from 'expo/config';
import { version } from './package.json';

const VARIANTS = {
  development: { name: 'Shop (Dev)', id: 'com.example.shop.dev', scheme: 'shop-dev' },
  preview: { name: 'Shop (Preview)', id: 'com.example.shop.preview', scheme: 'shop-preview' },
  production: { name: 'Shop', id: 'com.example.shop', scheme: 'shop' },
} as const;
type Variant = keyof typeof VARIANTS;
const isVariant = (v: string | undefined): v is Variant =>
  v !== undefined && Object.hasOwn(VARIANTS, v);
const raw = process.env.APP_VARIANT as string | undefined;
if (raw !== undefined && !isVariant(raw)) throw new Error(`Unknown APP_VARIANT "${raw}"`);
const variant: Variant = raw ?? 'development';
const { name, id, scheme } = VARIANTS[variant];
const EAS_PROJECT_ID = '00000000-0000-0000-0000-000000000000';
const LINK_HOST = 'app.example.com';
const links = variant === 'production';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name,
  slug: 'shop',
  version,
  scheme,
  ios: {
    ...config.ios,
    bundleIdentifier: id,
    ...(links && { associatedDomains: [`applinks:${LINK_HOST}`] }),
    privacyManifests: {
      NSPrivacyAccessedAPITypes: [
        {
          NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryUserDefaults',
          NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
        },
      ],
      NSPrivacyCollectedDataTypes: [
        {
          NSPrivacyCollectedDataType: 'NSPrivacyCollectedDataTypeCrashData',
          NSPrivacyCollectedDataTypeLinked: false,
          NSPrivacyCollectedDataTypeTracking: false,
          NSPrivacyCollectedDataTypePurposes: ['NSPrivacyCollectedDataTypePurposeAppFunctionality'],
        },
        {
          NSPrivacyCollectedDataType: 'NSPrivacyCollectedDataTypePerformanceData',
          NSPrivacyCollectedDataTypeLinked: false,
          NSPrivacyCollectedDataTypeTracking: false,
          NSPrivacyCollectedDataTypePurposes: ['NSPrivacyCollectedDataTypePurposeAnalytics'],
        },
        {
          NSPrivacyCollectedDataType: 'NSPrivacyCollectedDataTypeUserID',
          NSPrivacyCollectedDataTypeLinked: true,
          NSPrivacyCollectedDataTypeTracking: false,
          NSPrivacyCollectedDataTypePurposes: ['NSPrivacyCollectedDataTypePurposeAppFunctionality'],
        },
      ],
      NSPrivacyTracking: false,
    },
  },
  android: {
    ...config.android,
    package: id,
    allowBackup: false,
    ...(links && {
      intentFilters: [
        {
          action: 'VIEW',
          autoVerify: true,
          data: [{ scheme: 'https', host: LINK_HOST, pathPrefix: '/orders' }],
          category: ['BROWSABLE', 'DEFAULT'],
        },
      ],
    }),
  },
  experiments: { ...config.experiments, typedRoutes: true },
  runtimeVersion: { policy: 'fingerprint' },
  updates: {
    url: `https://u.expo.dev/${EAS_PROJECT_ID}`,
    checkAutomatically: 'ON_LOAD',
    fallbackToCacheTimeout: 0,
  },
  extra: { ...config.extra, eas: { projectId: EAS_PROJECT_ID }, variant },
});
