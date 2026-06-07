# Railway deployment using Twenty's official pre-built Docker image.
# The official entrypoint already maps Railway's PORT to Twenty's NODE_PORT.
# We disable the broken database migration script path to avoid "Cannot find module" errors.

FROM twentycrm/twenty:v2.9.1

ENV DISABLE_DB_MIGRATIONS=true
