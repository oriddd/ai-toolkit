import { resolveDeepLink } from '@features/links';
export function redirectSystemPath({ path }: { path: string; initial: boolean }): string | null {
  const route = resolveDeepLink(path);
  return route ? `/orders/${encodeURIComponent(route.params.id)}` : null;
}
