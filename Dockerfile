# ========================================================================
# Railway Optimized Dockerfile for Twenty CRM
#
# This root Dockerfile replaces Railway's slow railpack auto-builder
# with a multi-stage build that caches dependencies and reuses layers.
#
# Key optimizations:
# - Layer caching: deps only reinstall when package.json/yarn.lock change
# - Separate front-end and server builds for parallelization
# - Production-only dependencies in final image
# - Uses existing entrypoint.sh for DB setup/migrations
# ========================================================================

FROM node:24.15.0-alpine3.23 AS base
RUN apk add --no-cache curl
WORKDIR /app

# Limit Nx parallelism to avoid OOM on Railway builders
ENV NX_PARALLEL=1
# Cap Node.js heap and limit Go-based tools (tsgo) to 1 thread
# Railway builders typically have 4-8GB total RAM; leave headroom for OS/Docker
ENV NODE_OPTIONS="--max-old-space-size=2048"
ENV GOMAXPROCS=1

# ========================================================================
# Stage 1: Install frontend dependencies (cached layer)
# Only rebuilds when root package files or front package.jsons change
# ========================================================================
FROM base AS front-deps

COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches /app/.yarn/patches

COPY ./packages/twenty-ui/package.json /app/packages/twenty-ui/
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-front/package.json /app/packages/twenty-front/
COPY ./packages/twenty-front-component-renderer/package.json /app/packages/twenty-front-component-renderer/
COPY ./packages/twenty-sdk/package.json /app/packages/twenty-sdk/
COPY ./packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/

RUN yarn workspaces focus twenty twenty-front twenty-front-component-renderer twenty-ui twenty-shared twenty-sdk twenty-client-sdk \
    && yarn cache clean

# ========================================================================
# Stage 2: Install server dependencies (cached layer)
# Only rebuilds when root package files or server package.jsons change
# ========================================================================
FROM base AS server-deps

COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches /app/.yarn/patches

COPY ./packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY ./packages/twenty-server/package.json /app/packages/twenty-server/
COPY ./packages/twenty-server/patches /app/packages/twenty-server/patches
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/

RUN yarn workspaces focus twenty twenty-server twenty-emails twenty-shared twenty-client-sdk \
    && yarn cache clean

# ========================================================================
# Stage 3: Build server (cached when server source changes)
# ========================================================================
FROM server-deps AS server-build

COPY ./packages/twenty-emails /app/packages/twenty-emails
COPY ./packages/twenty-shared /app/packages/twenty-shared
COPY ./packages/twenty-client-sdk /app/packages/twenty-client-sdk
COPY ./packages/twenty-server /app/packages/twenty-server

RUN npx nx run twenty-server:lingui:extract && \
    npx nx run twenty-server:lingui:compile && \
    npx nx run twenty-emails:lingui:extract && \
    npx nx run twenty-emails:lingui:compile

RUN npx nx run twenty-server:build

# Clean build output (remove type declarations and tests, keep source maps for Sentry)
RUN find /app/packages/twenty-server/dist -name '*.d.ts' -delete \
 && rm -rf /app/packages/twenty-server/dist/packages/twenty-server/test

# Strip to production dependencies only
RUN yarn workspaces focus --production twenty-emails twenty-shared twenty-client-sdk twenty-server

# ========================================================================
# Stage 4: Build frontend (cached when front source changes)
# ========================================================================
FROM front-deps AS front-build

COPY ./packages/twenty-front /app/packages/twenty-front
COPY ./packages/twenty-front-component-renderer /app/packages/twenty-front-component-renderer
COPY ./packages/twenty-ui /app/packages/twenty-ui
COPY ./packages/twenty-shared /app/packages/twenty-shared
COPY ./packages/twenty-sdk /app/packages/twenty-sdk
COPY ./packages/twenty-client-sdk /app/packages/twenty-client-sdk

RUN npx nx run twenty-front:lingui:extract && \
    npx nx run twenty-front:lingui:compile

# Use pre-built frontend if available (host build), otherwise build now
RUN if [ -d /app/packages/twenty-front/build ]; then \
      echo "Using pre-built frontend from host"; \
    else \
      NODE_OPTIONS="--max-old-space-size=3072" npx nx build twenty-front; \
    fi

# ========================================================================
# Stage 5: Final production image (server + frontend)
# Small, lean runtime image with only what's needed
# ========================================================================
FROM node:24.15.0-alpine3.23 AS production

RUN apk add --no-cache \
    curl \
    postgresql18-client \
    jq

WORKDIR /app/packages/twenty-server

ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# Copy entrypoint script
COPY ./packages/twenty-docker/twenty/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Workspace root config (needed for Yarn PnP/node_modules resolution)
COPY --from=server-build /app/package.json /app/yarn.lock /app/.yarnrc.yml /app/
COPY --from=server-build /app/tsconfig.base.json /app/nx.json /app/
COPY --from=server-build /app/.yarn /app/.yarn
COPY --from=server-build /app/node_modules /app/node_modules

# Server package (compiled dist + package.json + src for runtime path resolution)
COPY --from=server-build /app/packages/twenty-server/package.json /app/packages/twenty-server/
COPY --from=server-build /app/packages/twenty-server/dist /app/packages/twenty-server/dist
COPY --from=server-build /app/packages/twenty-server/src /app/packages/twenty-server/src
COPY --from=server-build /app/packages/twenty-server/patches /app/packages/twenty-server/patches

# Workspace packages (dist + package.json; node_modules symlinks resolve to these)
COPY --from=server-build /app/packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY --from=server-build /app/packages/twenty-shared/dist /app/packages/twenty-shared/dist
COPY --from=server-build /app/packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY --from=server-build /app/packages/twenty-emails/dist /app/packages/twenty-emails/dist
COPY --from=server-build /app/packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/
COPY --from=server-build /app/packages/twenty-client-sdk/dist /app/packages/twenty-client-sdk/dist

# Frontend static build
COPY --from=front-build /app/packages/twenty-front/build /app/packages/twenty-server/dist/front

# Create storage directories
RUN mkdir -p /app/.local-storage /app/packages/twenty-server/.local-storage && \
    chown 1000:1000 /app/.local-storage /app/packages/twenty-server/.local-storage

USER 1000

EXPOSE 3000

CMD ["node", "dist/src/main"]
ENTRYPOINT ["/app/entrypoint.sh"]
