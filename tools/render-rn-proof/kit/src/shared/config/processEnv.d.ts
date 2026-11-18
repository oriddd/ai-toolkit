declare global {
  namespace NodeJS {
    interface ProcessEnv {
      EXPO_PUBLIC_API_BASE_URL?: string;
      EXPO_PUBLIC_APP_ENV?: string;
      EXPO_PUBLIC_SENTRY_DSN?: string;
    }
  }
}
export {};
