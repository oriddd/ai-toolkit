import type { QueryClient } from '@tanstack/react-query';
const created: QueryClient[] = [];
export const tracked = (client: QueryClient): QueryClient => {
  const { queries, mutations } = client.getDefaultOptions();
  client.setDefaultOptions({
    queries: { ...queries, gcTime: Infinity },
    mutations: { ...mutations, gcTime: Infinity },
  });
  created.push(client);
  return client;
};
export const clearTrackedClients = () => {
  for (const client of created.splice(0)) client.clear();
};
