import * as Sentry from '@sentry/react-native';
import type { AppEnv } from '@shared/config/env';
import type { AppInfo } from '@shared/config/appInfo';
import { scrubBreadcrumb, scrubEvent } from './scrubPii';
// shared/services/observability/initSentry.ts
export const navigationIntegration = Sentry.reactNavigationIntegration(); // screen-load spans, section 6

export function initSentry(env: AppEnv, app: AppInfo | null, crashReportsAllowed: () => boolean) {
  Sentry.init({
    dsn: env.sentryDsn, // public identifier, see react-native-security
    environment: env.name,
    ...(app && {
      release: `${app.appId}@${app.version}+${app.buildNumber}`,
      dist: app.buildNumber,
    }),
    enabled: !__DEV__,
    tracesSampleRate: env.name === 'production' ? 0.1 : 1.0,
    enableAutoPerformanceTracing: true,
    integrations: [navigationIntegration],
    beforeSend: (event) => (crashReportsAllowed() ? scrubEvent(event) : null), // scrub (section 2), and drop without consent
    beforeSendTransaction: (event) => (crashReportsAllowed() ? scrubEvent(event) : null),
    beforeBreadcrumb: (crumb) => (crashReportsAllowed() ? scrubBreadcrumb(crumb) : null),
  });
}
