#!/bin/sh
set -e

# Railway injects PORT; Twenty uses NODE_PORT. Map them.
export NODE_PORT=${PORT:-3000}

echo "Starting Twenty CRM server on port ${NODE_PORT}..."

# Skip the official entrypoint which has path issues with migration scripts.
# The official image's CMD is "node dist/main" — just run it directly.
exec "$@"
