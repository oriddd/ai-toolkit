import { z } from 'zod';
import { vm } from './messages';

export const emailField = z.string().trim().min(1, vm.required).pipe(z.email(vm.email));
export const passwordField = z.string().min(12, vm.passwordShort).regex(/\d/, vm.passwordDigit);
