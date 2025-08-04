#!/bin/bash
# Script to check BC initialization status

STATUS_FILE="/home/bc-init-status.txt"

if [ -f "$STATUS_FILE" ]; then
    echo "=== BC Server Initialization Status ==="
    echo ""
    cat "$STATUS_FILE"
    echo ""
    echo "=== Current Status ==="
    tail -n 1 "$STATUS_FILE"
else
    echo "No status file found. BC Server initialization may not have started yet."
fi

# Also check if BC is running
echo ""
echo "=== BC Server Process Check ==="
if pgrep -f "Microsoft.Dynamics.Nav.Server" > /dev/null; then
    echo "BC Server is running"
else
    echo "BC Server is not running"
fi