export const init = jest.fn();
export const captureException = jest.fn();
export const addBreadcrumb = jest.fn();
export const setUser = jest.fn();
export const reactNavigationIntegration = jest.fn(() => ({ registerNavigationContainer: jest.fn() }));
export const wrap = <T>(component: T): T => component;
