FROM mcr.microsoft.com/playwright:v1.47.0-jammy

WORKDIR /e2e

COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

COPY playwright.config.ts global-setup.ts ./
COPY specs ./specs

RUN mkdir -p reports playwright-report test-results

ENV BASE_URL=http://nest-1:3000

CMD ["npx", "playwright", "test"]
