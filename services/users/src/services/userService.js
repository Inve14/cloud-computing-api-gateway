import { AppError } from '../errors.js';
import * as userRepo from '../repositories/userRepository.js';

export async function getMe(pool, userId) {
  const user = await userRepo.findById(pool, userId);
  if (!user) throw new AppError(404, 'NOT_FOUND', 'User not found');
  return { data: user };
}
