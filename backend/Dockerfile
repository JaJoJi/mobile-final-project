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
CMD ["node", "dist/main.js"]
