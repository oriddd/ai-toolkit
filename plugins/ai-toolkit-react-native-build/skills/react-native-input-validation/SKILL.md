---
name: react-native-input-validation
description: >
  React Native input validation with zod schemas in a validation layer, react-hook-form, cross-field rules, schemas
  shared with API types. Use when adding a form or field rule, or parsing external data (API, deep link, storage).
  Never ad-hoc if checks in components.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# React Native Input Validation Skill
## When to use

Use whenever a rule decides whether data is acceptable: a form field, a request payload, a deep-link
parameter, a value read from storage. The validation layer owns the contract; components and
handlers assume data is already valid.

> `if (!email.includes('@')) setError(...)` inside a component or `onPress` handler is an
> anti-pattern. Write a schema.

## Layout

```
features/signup/model/
├── signupSchema.ts       # zod schema + inferred type
├── passwordRules.ts      # reusable field schemas
└── signupSchema.test.ts
shared/validation/
├── fieldSchemas.ts       # email, phone, money used across features
└── messages.ts           # validation message catalogue
```

## Dependencies

```json
{ "dependencies": { "zod": "^4.0.0", "react-hook-form": "^7.55.0", "@hookform/resolvers": "^5.1.0" } }
```

## 1. Field schemas, reusable and named

```ts
// shared/validation/fieldSchemas.ts
import { z } from 'zod';
import { vm } from './messages';

export const emailField = z.string().trim().min(1, vm.required).email(vm.email);
export const passwordField = z.string().min(12, vm.passwordShort).regex(/\d/, vm.passwordDigit);
```

## 2. Messages in one catalogue

```ts
// shared/validation/messages.ts
export const vm = {
  required: 'This field is required.',
  email: 'Enter a valid email address.',
  passwordShort: 'Use at least 12 characters.',
  passwordDigit: 'Include at least one number.',
  passwordMismatch: 'Passwords do not match.',
  serverRejected: 'This value was not accepted.',       // fallback for a server field code with no entry of its own
} as const;
```

No string literals inside `.min(...)` calls in feature schemas; reference the catalogue (and i18n it there).

## 3. Cross-field rules

```ts
// features/signup/model/signupSchema.ts
export const signupSchema = z
  .object({ email: emailField, password: passwordField, confirmPassword: z.string() })
  .refine((v) => v.password === v.confirmPassword, { path: ['confirmPassword'], message: vm.passwordMismatch });

export type SignupForm = z.infer<typeof signupSchema>;
```

Cross-field and conditional rules live in `.refine` / `.superRefine` on the object schema, never in the screen.

## 4. react-hook-form integration

```tsx
export function useSignupForm() {
  return useForm<SignupForm>({
    resolver: zodResolver(signupSchema),
    defaultValues: { email: '', password: '', confirmPassword: '' },
    mode: 'onBlur',
  });
}

export function SignupScreen() {
  const { control, handleSubmit } = useSignupForm();
  const { mutate, isPending } = useSignup();
  return (
    <>
      <FormTextField control={control} name="email" label="Email" testID="signup-email" />
      <FormTextField control={control} name="password" label="Password" secureTextEntry testID="signup-password" />
      <FormTextField control={control} name="confirmPassword" label="Confirm password" secureTextEntry testID="signup-confirm-password" />
      <Button title="Create account" disabled={isPending} onPress={() => void handleSubmit((v) => mutate(v))()} />
    </>
  );
}
```

`FormTextField` wraps `Controller` and renders `fieldState.error?.message`. The screen holds no rules.

## 5. Share schemas with API types

```ts
// features/orders/model/orderSchemas.ts
export const orderSchema = z.object({ id: z.string().brand<'OrderId'>(), total: z.number().nonnegative(), status: z.enum(['open', 'cancelled']) });
export type Order = z.infer<typeof orderSchema>;
export type OrderId = Order['id'];                       // branded by the schema, never hand-written
```

Types are inferred from schemas, never hand-written twice. Responses are parsed with the same schema
at the api-client edge (`schema.parse`, see `react-native-state-and-data`); a parse failure becomes an
`AppError` there, not a crash in a component.

## 6. Parse untrusted data at every boundary

```ts
const deepLinkParams = z.object({ orderId: z.string().uuid() });
export const parseOrderLink = (raw: unknown) => deepLinkParams.safeParse(raw);
```

Use `safeParse` where failure is expected (links, storage, forms) and `parse` at the api-client edge
where failure is an error to map. Apply the same to persisted values after app upgrades.

## 7. Server-side validation errors

Map a 422 body to field errors with `setError(field, { message })` inside the submit hook, via the
mapper's `ValidationError.fieldErrors` (`VALIDATION_FAILED`, see `react-native-error-handling`), so server and client rules show in the same place:

```ts
onError: (e) => {
  if (!(e instanceof ValidationError)) return;            // other AppErrors go to the toast/banner
  for (const [field, code] of Object.entries(e.fieldErrors))
    if (field in signupSchema.shape)                      // ignore fields this form does not render
      setError(field as keyof SignupForm, { message: code in vm ? vm[code as keyof typeof vm] : vm.serverRejected });
},
```

Messages come from the catalogue, never from the server's text.

## Do / Don't

- ✅ One schema per form or payload, next to its model; infer the type.
- ✅ Test every schema with valid, invalid and boundary values.
- ✅ Validate on the client for UX, and treat the server as the authority.
- ❌ Inline `if` checks or regexes in components, handlers or hooks.
- ❌ Hand-written duplicate interface beside a schema.
- ❌ Validation message literals scattered across schemas.
- ❌ Using `any`/`as` casts to bypass a failed parse.

## Cross-references

- `react-native-error-handling`: `VALIDATION_FAILED` mapping and message catalogue style.
- `react-native-state-and-data`: api-client parses responses with these schemas.
- `react-native-security`: validating deep links and untrusted input.
- `react-native-unit-tests`: schema tests and form behaviour tests.
