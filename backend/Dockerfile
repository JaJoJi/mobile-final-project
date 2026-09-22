# Full dependency set (dev + prod) — used only to compile TypeScript.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig*.json ./
COPY src ./src
RUN npm run build

# Production-only dependencies — no devDependencies in the final image.
FROM node:22-alpine AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build     /app/dist         ./dist
COPY package.json ./
EXPOSE 3000
# node:22-alpine ships a built-in non-root `node` user (uid 1000) — no
# runtime filesystem writes in this app (pino logs to stdout), so no
# extra chown needed.
USER node
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health/live', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"
CMD ["node", "dist/main.js"]
