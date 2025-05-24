#!/usr/bin/env bash
#
# Fetches the Chrome DevTools WebSocket debugger URL from the /json endpoint
# and connects with wscat.
#
# Usage: connect-chrome-debug.sh [port] [host]
# Defaults:
#   port: 9222
#   host: 127.0.0.1
#
# TMP_DIR=$(mktemp -d /tmp/chrome-debug-XXXXX)
# google-chrome --remote-debugging-port=9222 --user-data-dir="$TMP_DIR"
#

set -euo pipefail

# Default to localhost:9222 if not specified
PORT=${1:-9222}
HOST=${2:-127.0.0.1}

WEBSOCKET_URL=$(
  curl -s "http://${HOST}:${PORT}/json" \
    | jq -r '.[0].webSocketDebuggerUrl'
)
wscat -c "$WEBSOCKET_URL"
