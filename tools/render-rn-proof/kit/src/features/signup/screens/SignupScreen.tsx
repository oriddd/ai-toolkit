import { Button, Text } from 'react-native';
import { useRouter } from 'expo-router';
import { FormTextField } from '@shared/ui/FormTextField';
import { useSignup } from '../hooks/useSignup';
import { useSignupForm } from '../hooks/useSignupForm';

export function SignupScreen() {
  const router = useRouter();
  const { control, handleSubmit, setError, formState } = useSignupForm();
  const { mutate, isPending } = useSignup(setError);
  const submit = handleSubmit((v) => {
    mutate(v, {
      onSuccess: () => {
        router.replace('/sign-in');
      },
    });
  });
  return (
    <>
      <FormTextField control={control} name="email" label="Email" testID="signup-email" />
      <FormTextField control={control} name="password" label="Password" secureTextEntry testID="signup-password" />
      <FormTextField control={control} name="confirmPassword" label="Confirm password" secureTextEntry testID="signup-confirm-password" />
      {formState.errors.root?.server ? (
        <Text accessibilityRole="alert">{formState.errors.root.server.message}</Text>
      ) : null}
      <Button title="Create account" testID="signup-submit" disabled={isPending} onPress={() => void submit()} />
    </>
  );
}
