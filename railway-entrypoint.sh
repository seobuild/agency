#!/bin/sh
set -e

# Railway injects PORT; Twenty uses NODE_PORT. Map them.
export NODE_PORT=${PORT:-3000}

echo "Starting Twenty CRM server on port ${NODE_PORT}..."

# Run the official image entrypoint with all original arguments
exec /app/entrypoint.sh "$@"
