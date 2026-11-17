import { Button, Text, View } from 'react-native';
import { isAppError } from './AppError';
import { messageFor } from './errorMessages';

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const retryable = isAppError(error) && error.retryable;
  return (
    <View accessibilityRole="alert" testID="error-state">
      <Text>{messageFor(error)}</Text>
      {retryable && onRetry ? <Button title="Try again" onPress={onRetry} /> : null}
    </View>
  );
}
