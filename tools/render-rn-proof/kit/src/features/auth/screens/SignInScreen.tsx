import { Button } from 'react-native';
import { zodResolver } from '@hookform/resolvers/zod';
import { Link } from 'expo-router';
import { useForm } from 'react-hook-form';
import { ErrorState } from '@shared/errors/ErrorState';
import { FormTextField } from '@shared/ui/FormTextField';
import { useSignIn } from '../hooks/useSignIn';
import { signinSchema, type SigninForm } from '../model/signinSchema';

export function SignInScreen() {
  const { control, handleSubmit } = useForm<SigninForm>({
    resolver: zodResolver(signinSchema),
    defaultValues: { email: '', password: '' },
    mode: 'onBlur',
  });
  const { mutate, isPending, error } = useSignIn();
  return (
    <>
      <FormTextField control={control} name="email" label="Email" testID="signin-email" />
      <FormTextField control={control} name="password" label="Password" secureTextEntry testID="signin-password" />
      {error ? <ErrorState error={error} /> : null}
      <Button title="Sign in" testID="signin-submit" disabled={isPending} onPress={() => void handleSubmit((v) => { mutate(v); })()} />
      <Link href="/sign-up" testID="signin-create-account">
        Create account
      </Link>
    </>
  );
}
