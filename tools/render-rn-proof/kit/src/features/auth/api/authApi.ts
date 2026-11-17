import type { HttpClient } from '@shared/api-client/httpClient';
import { loginResponseSchema, type SigninForm } from '../model/signinSchema';

export const createAuthApi = (http: HttpClient) => ({
  login: (body: SigninForm) => http.request({ path: '/auth/login', method: 'POST', body }, loginResponseSchema),
});
