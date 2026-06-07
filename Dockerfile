# Railway deployment using Twenty's official pre-built Docker image.
# We override the entrypoint to map Railway's PORT to Twenty's NODE_PORT
# and disable the broken database migration script path.

FROM twentycrm/twenty:v2.9.1

ENV DISABLE_DB_MIGRATIONS=true

COPY railway-entrypoint.sh /app/railway-entrypoint.sh
RUN chmod +x /app/railway-entrypoint.sh

ENTRYPOINT ["/app/railway-entrypoint.sh"]
