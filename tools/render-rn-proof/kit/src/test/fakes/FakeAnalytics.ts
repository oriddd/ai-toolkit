import type { Analytics, AnalyticsEvent } from '@shared/services/analytics/events';

export class FakeAnalytics implements Analytics {
  readonly events: AnalyticsEvent[] = [];
  userId: string | null = null;

  track(event: AnalyticsEvent) {
    this.events.push(event);
  }

  setUserId(id: string | null) {
    this.userId = id;
  }
}
