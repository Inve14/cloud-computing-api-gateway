import crypto from 'crypto';
import bcrypt from 'bcrypt';
import { AppError } from '../errors.js';
import { config } from '../config/index.js';
import * as userRepo  from '../repositories/userRepository.js';
import * as tokenRepo from '../repositories/tokenRepository.js';

// Opaque refresh token format: "<uuid>.<64-hex-chars>"
// The UUID is the DB primary key (fast lookup).
// The hex secret is bcrypt-hashed and stored in token_hash (never stored raw).
function generateRefreshToken() {
  const tokenId     = crypto.randomUUID();
  const tokenSecret = crypto.randomBytes(32).toString('hex');
  return { tokenId, tokenSecret, raw: `${tokenId}.${tokenSecret}` };
}

function parseRefreshToken(raw) {
  const dot = raw.indexOf('.');
  if (dot === -1) return null;
  return { tokenId: raw.slice(0, dot), tokenSecret: raw.slice(dot + 1) };
}

export async function register(pool, { email, password, first_name, last_name, phone }) {
  const existing = await userRepo.findByEmail(pool, email);
  if (existing) throw new AppError(409, 'EMAIL_ALREADY_EXISTS', 'A user with this email already exists');

  const password_hash = await bcrypt.hash(password, 12);
  const user = await userRepo.create(pool, { email, password_hash, first_name, last_name, phone });

  // TODO: emit to dedicated audit log stream (structured event: user_registered)
  return user;
}

export async function login(pool, jwtSign, { email, password }) {
  const user  = await userRepo.findByEmail(pool, email);
  const valid = user ? await bcrypt.compare(password, user.password_hash) : false;

  // TODO: emit to dedicated audit log stream (event: login_success / login_failure)
  if (!valid) throw new AppError(401, 'INVALID_CREDENTIALS', 'Email not found or password incorrect');

  // Housekeep stale tokens for this user (best-effort, non-blocking).
  tokenRepo.deleteExpiredForUser(pool, user.id).catch(() => {});

  const { tokenId, tokenSecret, raw } = generateRefreshToken();
  const tokenHash = await bcrypt.hash(tokenSecret, 10);
  const expiresAt = new Date(Date.now() + config.jwt.refreshTtlDays * 86_400_000);

  await tokenRepo.create(pool, {
    id: tokenId,
    user_id: user.id,
    token_hash: tokenHash,
    expires_at: expiresAt,
  });

  const access_token = jwtSign({ sub: user.id, email: user.email, role: user.role, iss: 'users-service' });

  return {
    access_token,
    refresh_token: raw,
    token_type: 'Bearer',
    expires_in: config.jwt.accessTtlSec,
  };
}

export async function refresh(pool, jwtSign, { refresh_token }) {
  const parsed = parseRefreshToken(refresh_token);
  if (!parsed) throw new AppError(401, 'TOKEN_INVALID', 'Malformed refresh token');

  const { tokenId, tokenSecret } = parsed;
  const tokenRow = await tokenRepo.findById(pool, tokenId);

  if (!tokenRow) throw new AppError(401, 'TOKEN_EXPIRED', 'Refresh token has expired or does not exist');

  const valid = await bcrypt.compare(tokenSecret, tokenRow.token_hash);
  if (!valid) throw new AppError(401, 'TOKEN_INVALID', 'Refresh token is invalid');

  const user = await userRepo.findById(pool, tokenRow.user_id);
  if (!user) throw new AppError(401, 'TOKEN_INVALID', 'User no longer exists');

  const access_token = jwtSign({ sub: user.id, email: user.email, role: user.role, iss: 'users-service' });

  // TODO: emit to audit log stream (event: token_refreshed)
  return {
    access_token,
    token_type: 'Bearer',
    expires_in: config.jwt.accessTtlSec,
  };
}

export async function logout(pool, { refresh_token, userId }) {
  const parsed = parseRefreshToken(refresh_token);
  if (!parsed) return; // malformed token → idempotent no-op

  const tokenRow = await tokenRepo.findById(pool, parsed.tokenId);
  // Silently ignore tokens that don't belong to the authenticated user.
  if (!tokenRow || tokenRow.user_id !== userId) return;

  await tokenRepo.deleteById(pool, parsed.tokenId);

  // TODO: emit to audit log stream (event: logout)
}
