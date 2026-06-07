# Railway deployment using Twenty's official pre-built Docker image.
# This avoids long/complex source builds on Railway's infrastructure.
# The wrapper entrypoint ensures Railway's PORT env var maps to Twenty's NODE_PORT.

FROM twentycrm/twenty:v2.9.1

# Copy our Railway-specific wrapper entrypoint
# (must already be executable in git; chmod fails in upstream image)
COPY ./railway-entrypoint.sh /app/railway-entrypoint.sh

# The official image already exposes 3000 and has the app built.
# We just need to inject the port mapping at runtime.
CMD ["node", "dist/main"]
ENTRYPOINT ["/app/railway-entrypoint.sh"]
