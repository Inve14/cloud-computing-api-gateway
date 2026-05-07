import { AppError } from '../errors.js';

// Fastify preHandler that validates the RS256 Bearer token.
// On success, @fastify/jwt populates request.user with the decoded payload:
//   { sub, email, role, iat, exp }
export async function authenticate(request) {
  try {
    await request.jwtVerify();
  } catch {
    throw new AppError(401, 'UNAUTHORIZED', 'Invalid or expired access token');
  }
}
