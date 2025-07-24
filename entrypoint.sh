#!/bin/bash

set -e

echo "Starting Business Central Container using BC4Ubuntu approach..."

# Set default environment variables if not provided
export SA_PASSWORD=${SA_PASSWORD:-"YourPassword123"}

# Generate configuration template if it doesn't exist
if [ ! -f "/home/bcserver/CustomSettings.config.template" ]; then
    echo "Creating configuration template..."
    pwsh /home/create-config-template.ps1
fi

# Check if this is first run and initialize Wine if needed
if [ ! -f "/home/.wine-initialized" ]; then
    echo "First run detected, initializing Wine environment..."
    /home/init-wine.sh
    touch /home/.wine-initialized
    echo "Wine initialization completed"
fi

# Check if BC_AUTOSTART is set to false
if [ "${BC_AUTOSTART}" = "false" ]; then
    echo "BC_AUTOSTART is set to false. Container will stay running without starting BC Server."
    echo "To start BC Server manually, run one of these commands inside the container:"
    echo "  - /home/start-bcserver.sh"
    echo "  - /home/start-bcserver-workaround.sh"
    echo "  - /home/start-bcserver-final-fix.sh"
    echo ""
    echo "Container is ready for debugging..."
    # Keep container running
    tail -f /dev/null
else
    # Start the BC server
    echo "Starting BC Server..."
    # Try the final fix script if it exists
    if [ -f "/home/start-bcserver-final-fix.sh" ]; then
        echo "Using final fix script for BC Server..."
        exec /home/start-bcserver-final-fix.sh
    elif [ -f "/home/start-bcserver-workaround.sh" ]; then
        echo "Using workaround script to prevent culture duplicate errors..."
        exec /home/start-bcserver-workaround.sh
    else
        exec /home/start-bcserver.sh
    fi
fi
