import { parseEnv } from '@shared/config/env';
export const env = parseEnv({
  name: process.env.EXPO_PUBLIC_APP_ENV,
  apiBaseUrl: process.env.EXPO_PUBLIC_API_BASE_URL,
  sentryDsn: process.env.EXPO_PUBLIC_SENTRY_DSN ?? '',
});
