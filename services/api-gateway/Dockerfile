# --- Dependency stage: cache npm install separately from source changes ---
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

# --- Runtime stage: small alpine image, non-root user ---
FROM node:20-alpine

# Explicit numeric UID/GID (not just a named user): Kubernetes'
# runAsNonRoot pod security check can only verify a container is non-root
# statically, from the pod spec's runAsUser, when that UID is known ahead
# of time - it cannot resolve a named user (e.g. "app") to a UID without
# actually starting the container, so it refuses to start the container
# at all rather than guess. helm/taskflow's securityContext.pod.runAsUser
# (values.yaml) is set to this same 10001 - the two must stay in sync.
# (1000 was tried first and rejected at build time: node:20-alpine
# already has GID 1000 taken by its built-in "node" user.)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app

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
