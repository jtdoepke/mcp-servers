FROM node:22 AS builder

ARG SRC_REPO
ARG SRC_HASH

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends git

WORKDIR /repo
RUN git clone "$SRC_REPO" . \
    && git checkout "$SRC_HASH"

WORKDIR /app

RUN cp /repo/src/sequentialthinking/* ./ \
    && cp /repo/tsconfig.json /tsconfig.json

RUN --mount=type=cache,target=/root/.npm \
    npm install --ignore-scripts --omit-dev \
    && npm audit fix

RUN --mount=type=cache,target=/root/.npm-production \
    npm ci --ignore-scripts --omit-dev \
    && npm run build

# RUNTIME STAGE
FROM gcr.io/distroless/nodejs24-debian12:debug-nonroot

ENV NODE_ENV=production
WORKDIR /app

# Ensure we run as non-root user
USER 65532

# Copy built application and dependencies with proper ownership
COPY --from=builder --chown=65532:65532 /app/dist /app/dist
COPY --from=builder --chown=65532:65532 /app/node_modules /app/node_modules

CMD ["dist/index.js"]
