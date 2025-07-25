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

# Setup BC encryption keys using bash script
if [ ! -f "/home/bcserver/Keys/bc.key" ]; then
    echo "Setting up BC encryption..."
    /home/setup-bc-encryption.sh
fi

# Check if this is first run and initialize Wine if needed
if [ ! -f "/home/.wine-initialized" ]; then
    echo "First run detected, initializing Wine environment..."
    /home/init-wine.sh
    touch /home/.wine-initialized
    echo "Wine initialization completed"
fi

# Restore database if needed
export PATH="$PATH:/opt/mssql-tools18/bin"
if command -v sqlcmd >/dev/null 2>&1; then
    echo "Checking database..."
    /home/restore-database.sh
else
    echo "sqlcmd not found, skipping database restore"
    echo "Database must be restored manually"
fi

# Check if BC_AUTOSTART is set to false
if [ "${BC_AUTOSTART}" = "false" ]; then
    echo "BC_AUTOSTART is set to false. Container will stay running without starting BC Server."
    echo "To start BC Server manually, run:"
    echo "  /home/start-bcserver.sh"
    echo ""
    echo "Container is ready for debugging..."
    # Keep container running
    tail -f /dev/null
else
    # Start the BC server
    echo "Starting BC Server..."
    # Note: The custom Wine build includes locale fixes, eliminating the need for
    # the previous workaround scripts (now archived in legacy/culture-workarounds/)
    exec /home/start-bcserver.sh
fi
