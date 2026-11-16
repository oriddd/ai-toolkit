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
version: 1.1
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Input Validation Skill
## When to use

Use whenever a rule decides whether data is acceptable: a form field, a request payload, a deep-link
parameter, a value read from storage. The validation layer owns the contract; components and
handlers assume data is already valid.

> `if (!email.includes('@')) setError(...)` inside a component or `onPress` handler is an
> anti-pattern. Write a schema.

## Layout

```
features/signup/
├── model/
│   ├── signupSchema.ts       # zod schema + inferred form and request types
│   ├── passwordRules.ts      # reusable field schemas
│   └── signupSchema.test.ts
├── api/signupApi.ts          # the only caller of the http client (react-native-state-and-data)
└── hooks/useSignup.ts        # mutation + server field errors -> form (section 7)
shared/validation/
├── fieldSchemas.ts       # email, phone, money used across features
└── messages.ts           # validation message catalogue
```

## Dependencies

```json
{ "dependencies": { "zod": "^4.0.0", "react-hook-form": "^7.55.0", "@hookform/resolvers": "^7.0.0" } }
```

Type-checked together (2026-11-11) with zod 4.6, react-hook-form 7.92 and `@hookform/resolvers` 7.0 under the strict
`tsconfig` of `react-native-code-structure`; `zodResolver` takes a zod 4 schema directly.

## 1. Field schemas, reusable and named

```ts
// shared/validation/fieldSchemas.ts
import { z } from 'zod';
import { vm } from './messages';

export const emailField = z.string().trim().min(1, vm.required).pipe(z.email(vm.email)); // zod 4: z.email(), not .email()
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
export type SignupRequest = Pick<SignupForm, 'email' | 'password'>;   // what the server receives: no confirmPassword
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
  const { control, handleSubmit, setError } = useSignupForm();
  const { mutate, isPending } = useSignup(setError);         // section 7 maps server field errors into the form
  return (
    <>
      <FormTextField control={control} name="email" label="Email" testID="signup-email" />
      <FormTextField control={control} name="password" label="Password" secureTextEntry testID="signup-password" />
      <FormTextField control={control} name="confirmPassword" label="Confirm password" secureTextEntry testID="signup-confirm-password" />
      <Button title="Create account" testID="signup-submit" disabled={isPending} onPress={() => void handleSubmit((v) => mutate(v))()} />
    </>
  );
}
```

`FormTextField` is a small generic component of the app (`<T extends FieldValues>({ control, name, label, testID,
secureTextEntry })`) that wraps `Controller` around a `TextInput` and renders `fieldState.error?.message`. The screen holds no rules.

## 5. Share schemas with API types

```ts
// features/orders/model/orderSchemas.ts
export const orderSchema = z.object({
  id: z.string().brand<'OrderId'>(), title: z.string(), total: z.number().nonnegative(), status: z.enum(['open', 'cancelled']),
});
export type Order = z.infer<typeof orderSchema>;
export type OrderId = Order['id'];                       // branded by the schema, never hand-written
```

Types are inferred from schemas, never hand-written twice. Responses are parsed with the same schema
at the api-client edge (`schema.safeParse`, see `react-native-state-and-data`); a parse failure becomes an
`AppError` there, not a crash in a component.

## 6. Parse untrusted data at every boundary

```ts
const deepLinkParams = z.object({ orderId: z.uuid() });   // zod 4: z.uuid(), not z.string().uuid()
export const parseOrderLink = (raw: unknown) => deepLinkParams.safeParse(raw);
```

Use `safeParse` everywhere: where failure is expected (links, storage, forms) the result drives the flow, and
at the api-client edge a failed result is mapped to an `AppError` (no `ZodError` escapes). Apply the same to
persisted values after app upgrades.

## 7. Server-side validation errors

Map a 422 body to field errors with `setError(field, { message })` inside the submit hook, via the
mapper's `ValidationError.fieldErrors` (`VALIDATION_FAILED`, see `react-native-error-handling`), so server and client rules show in the same place.

**Wire contract:** the server's `field` is the wire path, the JSON key exactly as the request body sent it
(`body.customer_email` from a Python backend, see `python-error-handling`); `mapHttpError` strips the
`body.` prefix. Each form declares which wire keys it renders and under which form field, so snake_case
APIs and camelCase forms both work. A server error that matches no rendered field must not vanish: show the
`VALIDATION_FAILED` message as a form-level error instead.

The server's `code` is the backend's vocabulary, not a client catalogue key: a Python backend sends the pydantic
error type (`missing`, `string_too_short`, `value_error`; `FieldError.code` in `python-error-handling` §3), a Java
backend its own constraint codes. Map each rendered field's known codes to catalogue messages explicitly, next to
the wire key; an unmapped code gets `vm.serverRejected`.

```ts
// features/signup/api/signupApi.ts: the feature api is the only caller of the http client
export const createSignupApi = (http: HttpClient) => ({
  signup: (body: SignupRequest): Promise<void> => http.request({ path: '/signup', method: 'POST', body }, z.undefined()),
});
// features/signup/hooks/useSignupApi.ts, as useOrdersApi in react-native-state-and-data
export const useSignupApi = () => { const { http } = useServices(); return useMemo(() => createSignupApi(http), [http]); };
```

```ts
// features/signup/hooks/useSignup.ts
// wire key -> form field + server code -> message; Maps, so a key such as `toString` never hits a prototype member
type ServerField = { field: keyof SignupForm; messages: ReadonlyMap<string, string> };
const SERVER_FIELDS = new Map<string, ServerField>([
  ['email', { field: 'email', messages: new Map([['missing', vm.required], ['value_error', vm.email]]) }],
  ['password', { field: 'password', messages: new Map([['missing', vm.required], ['string_too_short', vm.passwordShort]]) }],
]);

export function useSignup(setError: UseFormSetError<SignupForm>) {
  const signupApi = useSignupApi();
  return useMutation({
    mutationFn: ({ email, password }: SignupForm) => signupApi.signup({ email, password }),   // never confirmPassword
    onError: (e) => {
      if (!(e instanceof ValidationError)) return;          // other AppErrors go to the toast/banner
      let matched = false;
      for (const [wireKey, code] of Object.entries(e.fieldErrors)) {
        const target = SERVER_FIELDS.get(wireKey);
        if (target) { setError(target.field, { message: target.messages.get(code) ?? vm.serverRejected }); matched = true; }
      }
      if (!matched) setError('root.server', { message: errorMessages.VALIDATION_FAILED });  // never silent
    },
  });
}
```

The screen renders `formState.errors.root?.server?.message` above the submit button. Messages come from
the catalogue, never from the server's text.

## Do / Don't

- ✅ One schema per form or payload, next to its model; infer the type.
- ✅ Test every schema with valid, invalid and boundary values.
- ✅ Validate on the client for UX, and treat the server as the authority.
- ✅ Send the request type (`SignupRequest`), never the whole form: confirmation fields stay on the device.
- ❌ Inline `if` checks or regexes in components, handlers or hooks.
- ❌ Hand-written duplicate interface beside a schema.
- ❌ Validation message literals scattered across schemas.
- ❌ Using `any`/`as` casts to bypass a failed parse.
- ❌ Looking up a server error code in the client catalogue by name, or calling the http client from a hook.

## Cross-references

- `react-native-error-handling`: `VALIDATION_FAILED` mapping and message catalogue style.
- `react-native-state-and-data`: api-client parses responses with these schemas.
- `react-native-security`: validating deep links and untrusted input.
- `react-native-unit-tests`: schema tests and form behaviour tests.
