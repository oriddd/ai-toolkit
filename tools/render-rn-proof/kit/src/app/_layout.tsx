import 'react-native-url-polyfill/auto';
import * as Sentry from '@sentry/react-native';
import { useNavigationContainerRef } from 'expo-router';
import { useEffect } from 'react';
import { AppProviders } from '@bootstrap/AppProviders';
import { env } from '@bootstrap/env';
import { RootNavigator } from '@bootstrap/RootNavigator';
import { readAppInfo } from '@shared/config/appInfo';
import { initSentry, navigationIntegration } from '@shared/services/observability/initSentry';
initSentry(env, readAppInfo(), () => false);
function RootLayout() {
  const navigationRef = useNavigationContainerRef();
  useEffect(() => {
    navigationIntegration.registerNavigationContainer(navigationRef);
  }, [navigationRef]);
  return (
    <AppProviders env={env}>
      <RootNavigator />
    </AppProviders>
  );
}
export default Sentry.wrap(RootLayout);
