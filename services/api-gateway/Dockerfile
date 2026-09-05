# --- Dependency stage: cache npm install separately from source changes ---
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

# --- Runtime stage: small alpine image, non-root user ---
FROM node:20-alpine

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src

# The runtime only needs `node`, not the npm CLI - removing it shrinks the
# image and drops npm's own bundled dependencies (a frequent source of
# unrelated CVE noise in vulnerability scans) from the final image.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

USER app

EXPOSE 8080

# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "src/index.js"]
