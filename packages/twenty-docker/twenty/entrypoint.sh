#!/bin/sh
set -e

echo "DEBUG: entrypoint.sh started, CWD=$(pwd)"

setup_and_migrate_db() {
    if [ "${DISABLE_DB_MIGRATIONS}" = "true" ]; then
        echo "Database setup and migrations are disabled, skipping..."
        return
    fi

    echo "DEBUG: Running database setup and migrations..."

    # Run setup and migration scripts
    echo "DEBUG: Checking if core schema exists..."
    has_schema=$(psql -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'core')" ${PG_DATABASE_URL})
    echo "DEBUG: has_schema=$has_schema"
    if [ "$has_schema" = "f" ]; then
        echo "Database appears to be empty, running migrations."
        echo "DEBUG: Running yarn database:init:prod..."
        yarn database:init:prod
        echo "DEBUG: yarn database:init:prod completed"
    fi

    echo "DEBUG: Running cache:flush before upgrade..."
    if ! yarn command:prod cache:flush; then
        echo "Warning: Failed to flush cache before upgrade, but continuing startup..."
    fi
    echo "DEBUG: cache:flush before upgrade completed"

    echo "DEBUG: Running upgrade..."
    if ! yarn command:prod upgrade; then
        echo "Warning: Upgrade completed with errors. Some workspaces may not be fully migrated. Check logs for details."
    fi
    echo "DEBUG: upgrade completed"

    echo "DEBUG: Running cache:flush after upgrade..."
    if ! yarn command:prod cache:flush; then
        echo "Warning: Failed to flush cache after upgrade, but continuing startup..."
    fi
    echo "DEBUG: cache:flush after upgrade completed"

    echo "Successfully migrated DB!"
}

register_background_jobs() {
    if [ "${DISABLE_CRON_JOBS_REGISTRATION}" = "true" ]; then
        echo "Cron job registration is disabled, skipping..."
        return
    fi

    echo "DEBUG: Registering background sync jobs..."
    if yarn command:prod cron:register:all; then
        echo "Successfully registered all background sync jobs!"
    else
        echo "Warning: Failed to register background jobs, but continuing startup..."
    fi
    echo "DEBUG: cron:register:all completed"
}

echo "DEBUG: Calling setup_and_migrate_db..."
setup_and_migrate_db
echo "DEBUG: setup_and_migrate_db completed"

echo "DEBUG: Calling register_background_jobs..."
register_background_jobs
echo "DEBUG: register_background_jobs completed"

# Continue with the original Docker command
echo "DEBUG: execing: $@"
exec "$@"
