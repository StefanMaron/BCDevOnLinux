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

# Start the BC server
echo "Starting BC Server..."
exec /home/start-bcserver.sh
