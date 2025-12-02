#!/bin/bash

set -e

echo "Starting Business Central Container using BC4Ubuntu approach..."

# Debug: Output environment variables for troubleshooting
echo ""
echo "=== Environment Variables (for troubleshooting) ==="
echo "  SA_PASSWORD: $(if [ -n "$SA_PASSWORD" ]; then echo '***set***'; else echo '(not set)'; fi)"
echo "  SQL_SERVER: ${SQL_SERVER:-(not set)}"
echo "  SQL_SERVER_PORT: ${SQL_SERVER_PORT:-(not set)}"
echo "  BC_AUTOSTART: ${BC_AUTOSTART:-(not set)}"
echo "  BC_ARTIFACT_URL: ${BC_ARTIFACT_URL:-(not set)}"
echo "  BC_VERSION: ${BC_VERSION:-(not set)}"
echo "  BC_COUNTRY: ${BC_COUNTRY:-(not set)}"
echo "  BC_TYPE: ${BC_TYPE:-(not set)}"
echo "  ADMIN_PASSWORD: $(if [ -n "$ADMIN_PASSWORD" ]; then echo '***set***'; else echo '(not set)'; fi)"
echo "  DATABASE_NAME: ${DATABASE_NAME:-(not set)}"
echo "  WINEDEBUG: ${WINEDEBUG:-(not set)}"
echo "=================================================="
echo ""

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

# Wine and .NET are already initialized in the base image (build-time)
# No runtime initialization needed - containers start immediately!
echo "✓ Wine and .NET pre-initialized in base image"
test -f "/home/.wine-initialized" && echo "✓ Initialization marker found" || echo "⚠ Warning: initialization marker missing"

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

# BCPasswordHasher binaries are pre-built and included in the image
# No runtime compilation needed

# Create default admin user on first run
if [ ! -f "/home/.admin-user-created" ] && command -v sqlcmd >/dev/null 2>&1; then
    echo "Creating default admin user..."
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-Admin123!}"

    # Wait for SQL Server to be ready
    for i in {1..30}; do
        if sqlcmd -S "${SQL_SERVER:-sql}" -U sa -P "${SA_PASSWORD}" -Q "SELECT 1" -C -N > /dev/null 2>&1; then
            echo "SQL Server is ready"
            break
        fi
        echo "Waiting for SQL Server... ($i/30)"
        sleep 2
    done

    # Create admin user using our SQL script
    if /home/scripts/bc/create-bc-user.sh admin "${ADMIN_PASSWORD}" SUPER 2>&1; then
        echo "✅ Default admin user created successfully"
        echo "   Username: admin"
        echo "   Password: ${ADMIN_PASSWORD}"
        echo "   Permission Set: SUPER"
        touch /home/.admin-user-created
    else
        echo "⚠️  Failed to create admin user (will retry on next start)"
    fi
fi

# Check if BC_AUTOSTART is set to false
if [ "${BC_AUTOSTART}" = "false" ]; then
    echo "BC_AUTOSTART is set to false. Container will stay running without starting BC Server."
    echo "To start BC Server manually, run:"
    echo "  /home/scripts/docker/start-bcserver.sh"
    echo ""
    echo "To create additional BC users, run:"
    echo "  /home/scripts/bc/create-bc-user.sh <username> <password> [permission_set]"
    echo "  Example: /home/scripts/bc/create-bc-user.sh john 'Pass123!' SUPER"
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
