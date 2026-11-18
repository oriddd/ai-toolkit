import type { Analytics } from './events';
export const noopAnalytics: Analytics = { track: () => undefined, setUserId: () => undefined };
