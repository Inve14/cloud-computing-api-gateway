import { AppError } from '../errors.js';
import * as userRepo from '../repositories/userRepository.js';

export async function getMe(pool, userId) {
  const user = await userRepo.findById(pool, userId);
  if (!user) throw new AppError(404, 'NOT_FOUND', 'User not found');
  return { data: user };
}

export async function updateMe(pool, userId, body) {
  const allowed = ['first_name', 'last_name', 'phone'];
  const fields = {};
  for (const key of allowed) {
    if (body[key] !== undefined) fields[key] = body[key];
  }
  const user = await userRepo.updateById(pool, userId, fields);
  if (!user) throw new AppError(404, 'NOT_FOUND', 'User not found');
  return { data: user };
}
