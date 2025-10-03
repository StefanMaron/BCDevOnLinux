#!/bin/bash

set -e

echo "Starting Business Central Container using BC4Ubuntu approach..."

# Source Wine environment (base image has Wine paths already configured)
if [ -f /home/scripts/wine/wine-env.sh ]; then
    source /home/scripts/wine/wine-env.sh
fi

# Set default environment variables if not provided
export SA_PASSWORD=${SA_PASSWORD:-"P@ssw0rd123!"}

# Skip template generation - use the provided CustomSettings.config
echo "Using provided CustomSettings.config (template generation skipped)"

# Make sure all scripts are executable
find /home/scripts -name "*.sh" -exec chmod +x {} \;

# Check if this is first run and initialize Wine if needed
if [ ! -f "/home/.wine-initialized" ]; then
    echo "First run detected, initializing Wine environment..."

    # Use base image runtime initialization scripts
    if [ -f "/usr/local/bin/wine-init-runtime.sh" ]; then
        echo "Running minimal Wine initialization..."
        /usr/local/bin/wine-init-runtime.sh
    fi

    # Install .NET 8 components at runtime (no Docker timeout here)
    # if [ -f "/usr/local/bin/wine-init-full.sh" ]; then
    #     echo "Installing .NET 8 runtime components..."
    #     /usr/local/bin/wine-init-full.sh
    # fi
    echo "Note: .NET 8 should be pre-installed in base image"

    touch /home/.wine-initialized
    echo "Wine and .NET initialization completed"
fi

# Check and cache BC artifacts
# Priority: 1) Pre-mounted artifacts, 2) Cached in volume, 3) Download fresh
echo "Checking BC artifacts..."
pwsh /home/scripts/bc/cache-artifacts.ps1
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to prepare BC artifacts"
    exit 1
fi

# Restore database if needed
export PATH="$PATH:/opt/mssql-tools18/bin"
if command -v sqlcmd >/dev/null 2>&1; then
    echo "Checking database..."
    /home/scripts/bc/restore-database.sh
else
    echo "sqlcmd not found, skipping database restore"
    echo "Database must be restored manually"
fi

# Check if BC_AUTOSTART is set to false
if [ "${BC_AUTOSTART}" = "false" ]; then
    echo "BC_AUTOSTART is set to false. Container will stay running without starting BC Server."
    echo "To start BC Server manually, run:"
    echo "  /home/scripts/docker/start-bcserver.sh"
    echo ""
    echo "To create a BC user, run:"
    echo "  /home/scripts/bc/create-bc-user.sh [username] [password] [permission_set]"
    echo ""
    echo "Container is ready for debugging..."
    # Keep container running
    tail -f /dev/null
else
    # Start the BC server
    echo "Starting BC Server..."
    # Note: The custom Wine build includes locale fixes, eliminating the need for
    # the previous workaround scripts (now archived in legacy/culture-workarounds/)
    exec /home/scripts/docker/start-bcserver.sh
fi
