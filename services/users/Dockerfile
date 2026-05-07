# =============================================================================
# Users Service — Multi-stage Dockerfile
# =============================================================================
# Stage 1 (builder): install production dependencies.
# Stage 2 (runtime): lean image, non-root user, only what is needed to run.
#
# Image tag is pinned to avoid unexpected breaking changes from upstream
# updates. Update deliberately and test before bumping.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: builder
# Installs production dependencies. node_modules is copied to the runtime
# stage, keeping the final image free of npm and build tooling.
# -----------------------------------------------------------------------------
FROM node:20.18-alpine AS builder

WORKDIR /app

# Copy manifests first to leverage Docker layer cache:
# npm ci only re-runs when package*.json changes.
COPY package*.json ./
RUN npm ci --omit=dev

# Copy application source after installing deps.
COPY src/ ./src/

# -----------------------------------------------------------------------------
# Stage 2: runtime
# Minimal image — only the built artefacts from the builder stage.
# Runs as a non-root user (principle of least privilege).
# -----------------------------------------------------------------------------
FROM node:20.18-alpine AS runtime

# Create a dedicated non-root user and group.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy everything produced by the builder stage with correct ownership.
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/src ./src
COPY --chown=appuser:appgroup package.json ./

USER appuser

EXPOSE 3002

# Docker liveness probe — matches GET /health (same endpoint Kong uses).
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3002/health || exit 1

CMD ["node", "src/server.js"]
