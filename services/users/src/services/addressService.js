import { AppError } from '../errors.js';
import * as addressRepo from '../repositories/addressRepository.js';

export async function listAddresses(pool, userId) {
  const addresses = await addressRepo.listByUserId(pool, userId);
  return { data: addresses };
}

export async function getAddress(pool, addressId, userId) {
  const address = await addressRepo.getById(pool, addressId);
  if (!address) throw new AppError(404, 'NOT_FOUND', 'Address not found');
  if (address.user_id !== userId) throw new AppError(403, 'FORBIDDEN', 'Access denied');
  return { data: address };
}

export async function createAddress(pool, userId, body) {
  const address = await addressRepo.create(pool, {
    userId,
    type:       body.type,
    street:     body.street,
    city:       body.city,
    zip_code:   body.zip_code,
    country:    body.country ?? 'IT',
    is_default: body.is_default ?? false,
  });
  return { data: address };
}

export async function updateAddress(pool, addressId, userId, body) {
  const existing = await addressRepo.getById(pool, addressId);
  if (!existing) throw new AppError(404, 'NOT_FOUND', 'Address not found');
  if (existing.user_id !== userId) throw new AppError(403, 'FORBIDDEN', 'Access denied');

  const allowed = ['street', 'city', 'zip_code', 'country', 'is_default'];
  const fields = {};
  for (const key of allowed) {
    if (body[key] !== undefined) fields[key] = body[key];
  }

  const address = await addressRepo.update(pool, {
    id: addressId,
    userId,
    fields,
    addressType: existing.type,
  });
  return { data: address };
}

export async function deleteAddress(pool, addressId, userId) {
  const existing = await addressRepo.getById(pool, addressId);
  if (!existing) throw new AppError(404, 'NOT_FOUND', 'Address not found');
  if (existing.user_id !== userId) throw new AppError(403, 'FORBIDDEN', 'Access denied');
  await addressRepo.remove(pool, addressId);
}
