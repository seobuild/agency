#!/bin/sh

# Railway injects PORT; Twenty uses NODE_PORT. Map them.
export NODE_PORT=${PORT:-3000}

echo "Starting Twenty CRM server on port ${NODE_PORT}..."
echo "Received command: $@"
echo "PWD: $(pwd)"
echo "DIR contents:"
ls -la

echo "Testing if dist/main.js exists:"
if [ -f "dist/main.js" ]; then
    echo "dist/main.js exists."
else
    echo "dist/main.js NOT FOUND"
    echo "dist directory contents:"
    ls -la dist/ 2>/dev/null || echo "No dist directory"
fi

# Skip the official entrypoint which has path issues with migration scripts.
# The official image's CMD is "node dist/main" — just run it directly.
echo "Starting application..."
exec node dist/main
