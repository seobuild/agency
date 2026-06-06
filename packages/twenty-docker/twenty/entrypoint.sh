#!/bin/sh
set -e

# Railway injects PORT; Twenty uses NODE_PORT. Map them.
export NODE_PORT=${PORT:-3000}

echo "Starting Twenty CRM server on port ${NODE_PORT}..."

if [ "${DISABLE_DB_MIGRATIONS}" != "true" ]; then
    echo "Checking database state..."
    has_schema=$(psql -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'core')" ${PG_DATABASE_URL})
    if [ "$has_schema" = "f" ]; then
        echo "Database is empty, running initial setup..."
        yarn database:init:prod
    fi
    echo "Running cache flush and upgrade..."
    yarn command:prod cache:flush || true
    yarn command:prod upgrade || true
    yarn command:prod cache:flush || true
    echo "Database migrations complete."
fi

if [ "${DISABLE_CRON_JOBS_REGISTRATION}" != "true" ]; then
    echo "Registering background jobs..."
    yarn command:prod cron:register:all || true
fi

echo "Starting application..."
exec "$@"
