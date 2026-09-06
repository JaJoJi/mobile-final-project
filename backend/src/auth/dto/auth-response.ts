/**
 * Shape returned by /auth/register, /auth/login, /auth/refresh.
 * Matches `docs/04-api-contracts.md` § 1.
 */
export interface AuthResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
}
