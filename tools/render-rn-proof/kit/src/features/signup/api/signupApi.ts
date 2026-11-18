import { z } from 'zod';
import type { HttpClient } from '@shared/api-client/httpClient';
import type { SignupRequest } from '../model/signupSchema';

export const createSignupApi = (http: HttpClient) => ({
  signup: (body: SignupRequest): Promise<void> =>
    http.request({ path: '/signup', method: 'POST', body }, z.undefined()),
});
