import { useServices } from '@shared/services/ServicesContext';
import type { Analytics } from './events';
export const useAnalytics = (): Analytics => useServices().analytics;
