import { useMutation } from '@tanstack/react-query';
import type { UseFormSetError } from 'react-hook-form';
import { ValidationError } from '@shared/errors/AppError';
import { errorMessages } from '@shared/errors/errorMessages';
import { vm } from '@shared/validation/messages';
import type { SignupForm } from '../model/signupSchema';
import { useSignupApi } from './useSignupApi';

type ServerField = { field: keyof SignupForm; messages: ReadonlyMap<string, string> };
const SERVER_FIELDS = new Map<string, ServerField>([
  ['email', { field: 'email', messages: new Map([['missing', vm.required], ['value_error', vm.email]]) }],
  ['password', { field: 'password', messages: new Map([['missing', vm.required], ['string_too_short', vm.passwordShort]]) }],
]);

export function useSignup(setError: UseFormSetError<SignupForm>) {
  const signupApi = useSignupApi();
  return useMutation({
    mutationFn: ({ email, password }: SignupForm) => signupApi.signup({ email, password }),
    onError: (e) => {
      if (!(e instanceof ValidationError)) return;
      let matched = false;
      for (const [wireKey, code] of Object.entries(e.fieldErrors)) {
        const target = SERVER_FIELDS.get(wireKey);
        if (target) {
          setError(target.field, { message: target.messages.get(code) ?? vm.serverRejected });
          matched = true;
        }
      }
      if (!matched) setError('root.server', { message: errorMessages.VALIDATION_FAILED });
    },
  });
}
