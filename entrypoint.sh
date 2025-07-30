#!/bin/bash

set -e

echo "Starting Business Central Container using BC4Ubuntu approach..."

# Source Wine environment
if [ -f /home/wine-env.sh ]; then
    source /home/wine-env.sh
fi

# Set default environment variables if not provided
export SA_PASSWORD=${SA_PASSWORD:-"P@ssw0rd123!"}

# Skip template generation - use the provided CustomSettings.config
echo "Using provided CustomSettings.config (template generation skipped)"

# Setup BC encryption keys using bash script
# if [ ! -f "/home/bcserver/Keys/bc.key" ]; then
#     echo "Setting up BC encryption..."
#     /home/setup-bc-encryption.sh
# fi

# Check if this is first run and initialize Wine if needed
if [ ! -f "/home/.wine-initialized" ]; then
    echo "First run detected, initializing Wine environment..."
    /home/init-wine.sh
    touch /home/.wine-initialized
    echo "Wine initialization completed"
fi

# Restore database if needed
# export PATH="$PATH:/opt/mssql-tools18/bin"
# if command -v sqlcmd >/dev/null 2>&1; then
#     echo "Checking database..."
#     /home/restore-database.sh
# else
#     echo "sqlcmd not found, skipping database restore"
#     echo "Database must be restored manually"
# fi

# Setup BC Reporting Service (Proof of Concept)
# Disabled for BC v26 - SideServices directory not available
# if [ -f "/home/setup-reporting-service-poc.sh" ]; then
#     echo "Setting up BC Reporting Service..."
#     /home/setup-reporting-service-poc.sh
#     echo "Reporting service setup completed"
# fi

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
