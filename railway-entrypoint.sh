#!/bin/sh
set -e

# Railway injects PORT; Twenty uses NODE_PORT. Map them.
export NODE_PORT=${PORT:-3000}

echo "Starting Twenty CRM server on port ${NODE_PORT}..."
echo "Received command: $@"

# Skip the official entrypoint which has path issues with migration scripts.
# The official image's CMD is "node dist/main" — just run it directly.
if [ $# -eq 0 ]; then
    echo "No command provided, defaulting to 'node dist/main'"
    exec node dist/main
else
    exec "$@"
fi
