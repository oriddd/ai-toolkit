import { z } from 'zod';
import { emailField } from '@shared/validation/fieldSchemas';
import { vm } from '@shared/validation/messages';

export const signinSchema = z.object({ email: emailField, password: z.string().min(1, vm.required) });
export type SigninForm = z.infer<typeof signinSchema>;
export const loginResponseSchema = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1),
  userId: z.string().min(1),
});
