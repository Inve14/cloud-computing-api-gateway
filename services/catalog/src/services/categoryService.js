import { AppError } from '../errors.js';
import * as categoryRepo from '../repositories/categoryRepository.js';

export async function listCategories(pool) {
  return categoryRepo.listCategories(pool);
}

export async function getCategoryById(pool, id) {
  const category = await categoryRepo.getCategoryById(pool, id);
  if (!category) throw new AppError(404, 'NOT_FOUND', 'Category not found');
  return category;
}
