import type { PropsWithChildren } from 'react';
import { Button, Text, View } from 'react-native';
import { ErrorBoundary, type FallbackProps } from 'react-error-boundary';
import { useErrorReporter } from './reportError';

function CrashScreen({ onRestart }: { onRestart: () => void }) {
  return (
    <View accessibilityRole="alert">
      <Text>Something went wrong.</Text>
      <Button title="Restart" onPress={onRestart} />
    </View>
  );
}

const CrashFallback = ({ resetErrorBoundary }: FallbackProps) => (
  <CrashScreen onRestart={resetErrorBoundary} />
);

export const AppErrorBoundary = ({ children }: PropsWithChildren) => {
  const reporter = useErrorReporter();
  return (
    <ErrorBoundary
      onError={(error, info) => {
        reporter.report(error, { componentStack: info.componentStack });
      }}
      FallbackComponent={CrashFallback}
    >
      {children}
    </ErrorBoundary>
  );
};
