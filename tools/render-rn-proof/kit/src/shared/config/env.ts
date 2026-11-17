import { z } from 'zod';
// shared/config/env.ts: build-time configuration, all public (react-native-security §2), parsed once at startup
const appEnvSchema = z.object({
  name: z.enum(['development', 'staging', 'production']),
  apiBaseUrl: z.url({ protocol: /^https$/ }),
  sentryDsn: z.string(),
});
export type AppEnv = z.infer<typeof appEnvSchema>;
export const parseEnv = (raw: unknown): AppEnv => appEnvSchema.parse(raw); // a bad build fails at launch, loudly
