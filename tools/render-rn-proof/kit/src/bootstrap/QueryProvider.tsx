import { useState, type PropsWithChildren } from 'react';
import { AppState } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import {
  focusManager,
  MutationCache,
  onlineManager,
  QueryCache,
  QueryClient,
  QueryClientProvider,
} from '@tanstack/react-query';
import { UnauthorizedError } from '@shared/errors/AppError';
import { isReportable, type ErrorReporter } from '@shared/errors/reportError';
import { signOut } from '@shared/session/signOut';
import { useServices, type Services } from '@shared/services/ServicesContext';
onlineManager.setEventListener((set) =>
  NetInfo.addEventListener((s) => {
    set(!!s.isConnected);
  }),
);
focusManager.setEventListener((handleFocus) => {
  // React Native has no window focus: use AppState
  const sub = AppState.addEventListener('change', (state) => {
    handleFocus(state === 'active');
  });
  return () => {
    sub.remove();
  };
});

type QueryClientDeps = {
  errorReporter: ErrorReporter;
  onUnauthorized: (client: QueryClient) => void; // the client it was built into: sign-out clears its cache
};

// exported so the retry, reporting and sign-out policy is unit-tested without rendering the provider
export const createQueryClient = ({ errorReporter, onUnauthorized }: QueryClientDeps) => {
  const handleError = (e: unknown) => {
    if (e instanceof UnauthorizedError)
      onUnauthorized(client); // refresh already failed (section 1): the session is over
    else if (isReportable(e)) errorReporter.report(e);
  };
  const client = new QueryClient({
    queryCache: new QueryCache({ onError: handleError }),
    mutationCache: new MutationCache({ onError: handleError }),
    defaultOptions: {
      queries: { retry: (n, e) => n < 2 && e.retryable, networkMode: 'offlineFirst' },
      mutations: { retry: 0 },
    },
  });
  return client;
};

export const createAppQueryClient = ({ errorReporter, secure }: Services) =>
  createQueryClient({
    errorReporter,
    onUnauthorized: (client) => {
      signOut(client, secure).catch((e: unknown) => {
        errorReporter.report(e);
      }); // react-native-security §1
    },
  });

export const QueryProvider = ({ children }: PropsWithChildren) => {
  const services = useServices(); // the client lives inside the services provider
  const [client] = useState(() => createAppQueryClient(services));
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
};
