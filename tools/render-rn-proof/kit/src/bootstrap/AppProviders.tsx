import { useState, type PropsWithChildren } from 'react';
import type { AppEnv } from '@shared/config/env';
import { ServicesProvider } from '@shared/services/ServicesContext';
import { createServices } from './createServices';
import { QueryProvider } from './QueryProvider';
export const AppProviders = ({ env, children }: PropsWithChildren<{ env: AppEnv }>) => {
  const [services] = useState(() => createServices(env));
  return (
    <ServicesProvider value={services}>
      <QueryProvider>{children}</QueryProvider>
    </ServicesProvider>
  );
};
