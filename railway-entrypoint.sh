#!/bin/sh
export NODE_PORT=${PORT:-3000}
exec node dist/main
