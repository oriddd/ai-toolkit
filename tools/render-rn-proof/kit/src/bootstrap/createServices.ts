import * as Sentry from '@sentry/react-native';
import { anonymousSession, createHttpClient } from '@shared/api-client/httpClient';
import type { AppEnv } from '@shared/config/env';
import { createConsentStore } from '@shared/consent/consent';
import { createAuthSession } from '@shared/session/createAuthSession';
import { createConsentedAnalytics } from '@shared/services/analytics/ConsentedAnalytics';
import { noopAnalytics } from '@shared/services/analytics/NoopAnalytics';
import { createLogger } from '@shared/services/logger/SentryBreadcrumbLogger';
import { createSentryErrorReporter } from '@shared/services/observability/SentryErrorReporter';
import { createExpoSecureStore } from '@shared/services/secure-storage/SecureStore';
import type { Services } from '@shared/services/ServicesContext';
import { createMemoryStorage } from '@shared/services/storage/MemoryStorage';
export const createServices = (env: AppEnv): Services => {
  const secure = createExpoSecureStore('app');
  const session = createAuthSession(secure, createHttpClient(env.apiBaseUrl, anonymousSession));
  const storage = createMemoryStorage();
  const consent = createConsentStore(storage);
  return {
    http: createHttpClient(env.apiBaseUrl, session),
    secure,
    storage,
    consent,
    logger: createLogger(Sentry),
    errorReporter: createSentryErrorReporter(),
    analytics: createConsentedAnalytics(noopAnalytics, consent),
  };
};
