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
    echo "Attempting to load module..."
    node -e "require('./dist/main.js')" 2>/tmp/module_error.txt
    if [ $? -ne 0 ]; then
        echo "Module load FAILED:"
        cat /tmp/module_error.txt
        echo "Checking @twentyhq packages in node_modules:"
        ls -la node_modules/@twentyhq 2>/dev/null || echo "No @twentyhq directory"
    else
        echo "Module load successful."
    fi
else
    echo "dist/main.js NOT FOUND"
    echo "dist directory contents:"
    ls -la dist/ 2>/dev/null || echo "No dist directory"
fi

# Skip the official entrypoint which has path issues with migration scripts.
# The official image's CMD is "node dist/main" — just run it directly.
if [ $# -eq 0 ]; then
    echo "No command provided, defaulting to 'node dist/main'"
    exec node dist/main
else
    exec "$@"
fi
