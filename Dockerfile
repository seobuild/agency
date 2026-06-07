# Railway deployment using Twenty's official pre-built Docker image.
# This avoids long/complex source builds on Railway's infrastructure.
# The wrapper entrypoint ensures Railway's PORT env var maps to Twenty's NODE_PORT.

FROM twentycrm/twenty:latest

WORKDIR /app

# Copy our Railway-specific wrapper entrypoint
COPY ./railway-entrypoint.sh /app/railway-entrypoint.sh
RUN chmod +x /app/railway-entrypoint.sh

# The official image already exposes 3000 and has the app built.
# We just need to inject the port mapping at runtime.
ENTRYPOINT ["/app/railway-entrypoint.sh"]
