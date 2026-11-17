export type AnalyticsEvent =
  | { name: 'order_placed'; props: { orderId: string; itemCount: number } }
  | { name: 'signup_completed'; props: { method: 'email' | 'apple' } };
export interface Analytics {
  track(event: AnalyticsEvent): void;
  setUserId(id: string | null): void;
}
