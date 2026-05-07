// TODO: Replace with real JWT validation when users service implements
//       RS256 signing. Will read `role` from JWT payload claims.

import { AppError } from '../errors.js';

export async function requireAdmin(request) {
  const role = request.headers['x-user-role'];

  if (!role) {
    throw new AppError(401, 'UNAUTHORIZED', 'Authentication required');
  }

  if (role !== 'admin') {
    throw new AppError(403, 'FORBIDDEN', 'Admin role required');
  }
}
