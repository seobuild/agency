# Railway-compatible wrapper for Twenty's official Dockerfile
# Removes VOLUME directive (Railway handles volumes separately)
# Uses the 'twenty' target (server + frontend, no bundled DB)

# Import the official Twenty Dockerfile up to the twenty target
# We need to inline it without the VOLUME line for Railway compatibility

# ===========================================================================
# Dependency stages (from packages/twenty-docker/twenty/Dockerfile)
# ===========================================================================

FROM node:24.15.0-alpine3.23 AS front-deps

WORKDIR /app

COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches /app/.yarn/patches

COPY ./packages/twenty-ui/package.json /app/packages/twenty-ui/
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-front/package.json /app/packages/twenty-front/
COPY ./packages/twenty-front-component-renderer/package.json /app/packages/twenty-front-component-renderer/
COPY ./packages/twenty-sdk/package.json /app/packages/twenty-sdk/
COPY ./packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/

RUN yarn workspaces focus twenty twenty-front twenty-front-component-renderer twenty-ui twenty-shared twenty-sdk twenty-client-sdk && yarn cache clean && npx nx reset


FROM node:24.15.0-alpine3.23 AS server-deps

WORKDIR /app

COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches /app/.yarn/patches

COPY ./packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY ./packages/twenty-server/package.json /app/packages/twenty-server/
COPY ./packages/twenty-server/patches /app/packages/twenty-server/patches
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/

RUN yarn workspaces focus twenty twenty-server twenty-emails twenty-shared twenty-client-sdk && yarn cache clean && npx nx reset


FROM server-deps AS twenty-server-build

COPY ./packages/twenty-emails /app/packages/twenty-emails
COPY ./packages/twenty-shared /app/packages/twenty-shared
COPY ./packages/twenty-client-sdk /app/packages/twenty-client-sdk
COPY ./packages/twenty-server /app/packages/twenty-server

RUN npx nx run twenty-server:lingui:extract && \
    npx nx run twenty-server:lingui:compile && \
    npx nx run twenty-emails:lingui:extract && \
    npx nx run twenty-emails:lingui:compile

RUN npx nx run twenty-server:build

# Clean server build output
RUN find /app/packages/twenty-server/dist -name '*.d.ts' -delete \
 && rm -rf /app/packages/twenty-server/dist/packages/twenty-server/test

RUN yarn workspaces focus --production twenty-emails twenty-shared twenty-client-sdk twenty-server


FROM front-deps AS twenty-front-build

COPY ./packages/twenty-front /app/packages/twenty-front
COPY ./packages/twenty-front-component-renderer /app/packages/twenty-front-component-renderer
COPY ./packages/twenty-ui /app/packages/twenty-ui
COPY ./packages/twenty-shared /app/packages/twenty-shared
COPY ./packages/twenty-sdk /app/packages/twenty-sdk
COPY ./packages/twenty-client-sdk /app/packages/twenty-client-sdk
RUN npx nx run twenty-front:lingui:extract && \
    npx nx run twenty-front:lingui:compile

# Use pre-built frontend if available
RUN if [ -d /app/packages/twenty-front/build ]; then \
      echo "Using pre-built frontend from host"; \
    else \
      NODE_OPTIONS="--max-old-space-size=8192" npx nx build twenty-front; \
    fi


# ===========================================================================
# Target: twenty (server + frontend) - Railway compatible, NO VOLUME directive
# ===========================================================================

FROM node:24.15.0-alpine3.23 AS production

RUN apk add --no-cache \
    curl \
    postgresql18-client \
    jq

COPY ./packages/twenty-docker/twenty/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
WORKDIR /app/packages/twenty-server

ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# Workspace root config
COPY --from=twenty-server-build /app/package.json /app/yarn.lock /app/.yarnrc.yml /app/
COPY --from=twenty-server-build /app/tsconfig.base.json /app/nx.json /app/
COPY --from=twenty-server-build /app/.yarn /app/.yarn
COPY --from=twenty-server-build /app/node_modules /app/node_modules

# Server package (compiled dist + package.json only, no src/)
COPY --from=twenty-server-build /app/packages/twenty-server/package.json /app/packages/twenty-server/
COPY --from=twenty-server-build /app/packages/twenty-server/dist /app/packages/twenty-server/dist
COPY --from=twenty-server-build /app/packages/twenty-server/patches /app/packages/twenty-server/patches

# Workspace packages
COPY --from=twenty-server-build /app/packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY --from=twenty-server-build /app/packages/twenty-shared/dist /app/packages/twenty-shared/dist
COPY --from=twenty-server-build /app/packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY --from=twenty-server-build /app/packages/twenty-emails/dist /app/packages/twenty-emails/dist
COPY --from=twenty-server-build /app/packages/twenty-client-sdk/package.json /app/packages/twenty-client-sdk/
COPY --from=twenty-server-build /app/packages/twenty-client-sdk/dist /app/packages/twenty-client-sdk/dist

# Frontend static build
COPY --from=twenty-front-build /app/packages/twenty-front/build /app/packages/twenty-server/dist/front

# Create storage directories (NO VOLUME directive for Railway)
RUN mkdir -p /app/.local-storage /app/packages/twenty-server/.local-storage && \
    chown 1000:1000 /app/.local-storage /app/packages/twenty-server/.local-storage

USER 1000

EXPOSE 3000

CMD ["node", "dist/main"]
ENTRYPOINT ["/app/entrypoint.sh"]
