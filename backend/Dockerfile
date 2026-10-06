# One pinned base for every stage (version + digest, #285) -- bump here
# deliberately; a floating tag makes old builds unreproducible. A named
# stage rather than `ARG` + `FROM ${...}`: Checkov can't resolve build
# args, so it read the ARG form as an untagged image (CKV_DOCKER_7).
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS base

# Full dependency set (dev + prod) — used only to compile TypeScript.
FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig*.json ./
COPY src ./src
RUN npm run build

# Production-only dependencies — no devDependencies in the final image.
FROM base AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM base AS runtime
# Static OCI metadata; revision/created/version are added per build by
# the Jenkinsfile (`docker build --label ...`) so Docker Hub images trace
# back to the exact commit.
LABEL org.opencontainers.image.title="rival-arena-backend" \
      org.opencontainers.image.description="Rival Arena game backend (NestJS)" \
      org.opencontainers.image.source="https://github.com/JaJoJi/mobile-final-project"
WORKDIR /app
ENV NODE_ENV=production
# Files stay root-owned (read-only to the app); the process runs as the
# image's built-in unprivileged `node` user (Checkov CKV_DOCKER_3, #285).
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build     /app/dist         ./dist
COPY package.json ./
# The app runs with plain `node`; npm/npx/corepack/yarn that ship with the
# base image are never used at runtime, and npm's bundled deps (pacote,
# sigstore, brace-expansion, ...) were all 8 HIGH CVEs Trivy found in this
# image (2026-09-27). Remove them instead of ignoring them.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
      /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
      /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
USER node
EXPOSE 3000
# Liveness only (process up) — readiness (/health/ready) depends on
# Postgres/Redis and is for the load balancer, not for restarting.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3     CMD wget -qO- "http://127.0.0.1:${NEST_PORT:-3000}/health/live" >/dev/null || exit 1
CMD ["node", "dist/main.js"]
