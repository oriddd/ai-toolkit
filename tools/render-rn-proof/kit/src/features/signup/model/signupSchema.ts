import { z } from 'zod';
import { emailField, passwordField } from '@shared/validation/fieldSchemas';
import { vm } from '@shared/validation/messages';

export const signupSchema = z
  .object({ email: emailField, password: passwordField, confirmPassword: z.string() })
  .refine((v) => v.password === v.confirmPassword, {
    path: ['confirmPassword'],
    message: vm.passwordMismatch,
  });

export type SignupForm = z.infer<typeof signupSchema>;
export type SignupRequest = Pick<SignupForm, 'email' | 'password'>;
