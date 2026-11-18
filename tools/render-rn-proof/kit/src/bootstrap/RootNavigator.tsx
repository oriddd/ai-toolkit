import { Stack } from 'expo-router';
import { useSessionStore } from '@shared/state/useSessionStore';

export const RootNavigator = () => {
  const signedIn = useSessionStore((s) => s.userId !== null);
  return (
    <Stack>
      <Stack.Protected guard={signedIn}>
        <Stack.Screen name="orders/index" />
        <Stack.Screen name="orders/[id]" />
      </Stack.Protected>
      <Stack.Protected guard={!signedIn}>
        <Stack.Screen name="sign-in" />
        <Stack.Screen name="sign-up" />
      </Stack.Protected>
    </Stack>
  );
};
