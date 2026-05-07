// JWT-based authentication and authorisation for the Catalog service.
//
// authenticate() — verifies the RS256 Bearer token issued by the Users service.
//   On success, @fastify/jwt populates request.user with the decoded payload:
//     { sub, email, role, iat, exp }
//
// requireAdmin() — calls authenticate(), then asserts role === 'admin'.

import { AppError } from '../errors.js';

export async function authenticate(request) {
  try {
    await request.jwtVerify();
  } catch {
    throw new AppError(401, 'UNAUTHORIZED', 'Invalid or expired access token');
  }
}

export async function requireAdmin(request) {
  await authenticate(request);

  if (request.user?.role !== 'admin') {
    throw new AppError(403, 'FORBIDDEN', 'Admin role required');
  }
}
