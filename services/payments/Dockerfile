# =============================================================================
# Payments Service — Multi-stage Dockerfile
# =============================================================================

FROM node:20.18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src/ ./src/

# -----------------------------------------------------------------------------
FROM node:20.18-alpine AS runtime

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/src ./src
COPY --chown=appuser:appgroup package.json ./

USER appuser

EXPOSE 3004

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3004/health || exit 1

CMD ["node", "src/server.js"]
