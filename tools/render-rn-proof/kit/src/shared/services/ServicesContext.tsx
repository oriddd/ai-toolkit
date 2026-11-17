import { createContext, useContext } from 'react';
import type { HttpClient } from '@shared/api-client/httpClient';
import type { ConsentStore } from '@shared/consent/consent';
import type { ErrorReporter } from '@shared/errors/reportError';
import type { Analytics } from './analytics/events';
import type { Logger } from './logger/Logger';
import type { SecureStore } from './secure-storage/SecureStore';
import type { KeyValueStorage } from './storage/KeyValueStorage';
export interface Services {
  http: HttpClient;
  storage: KeyValueStorage;
  secure: SecureStore;
  consent: ConsentStore;
  logger: Logger;
  errorReporter: ErrorReporter;
  analytics: Analytics;
}
const ServicesContext = createContext<Services | null>(null);
export const ServicesProvider = ServicesContext.Provider;
export const useServices = (): Services => {
  const s = useContext(ServicesContext);
  if (!s) throw new Error('ServicesProvider missing');
  return s;
};
