import type { PropsWithChildren } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { anonymousSession, createHttpClient } from '@shared/api-client/httpClient';
import { createConsentStore } from '@shared/consent/consent';
import { ServicesProvider, type Services } from '@shared/services/ServicesContext';
import { FakeAnalytics } from './fakes/FakeAnalytics';
import { FakeKeyValueStorage } from './fakes/FakeKeyValueStorage';
import { FakeSecureStore } from './fakes/FakeSecureStore';
import { tracked } from './queryClients';

const noop = () => undefined;

export const fakeServices = (): Services => {
  const storage = new FakeKeyValueStorage();
  return {
    http: createHttpClient('https://api.test', anonymousSession),
    storage,
    secure: new FakeSecureStore(),
    consent: createConsentStore(storage),
    logger: { debug: noop, info: noop, warn: noop, error: noop },
    errorReporter: { report: noop },
    analytics: new FakeAnalytics(),
  };
};

export const testProviders = (services: Services = fakeServices()) => {
  const client = tracked(new QueryClient({ defaultOptions: { queries: { retry: false } } }));
  return ({ children }: PropsWithChildren) => (
    <ServicesProvider value={services}>
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    </ServicesProvider>
  );
};
