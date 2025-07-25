#!/bin/bash

set -e

echo "Starting BC Server..."

# Historical Note:
# This script previously had multiple variants (workaround and final-fix) to handle
# Wine culture/locale issues that caused BC to fail with "'en-US' is not a valid language code".
# These workarounds are no longer needed since we now use a custom Wine build with locale fixes.
# The old scripts are preserved in legacy/culture-workarounds/ for reference.

# Set Wine environment variables following BC4Ubuntu methodology
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"
export WINE_SKIP_GECKO_INSTALLATION=1
export WINE_SKIP_MONO_INSTALLATION=1

# Standard locale settings (no special workarounds needed with custom Wine)
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

# Ensure virtual display is running
if ! pgrep -f "Xvfb :0" > /dev/null; then
    echo "Starting Xvfb for Wine..."
    # Clean up any stale lock files first
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
    sleep 2
else
    echo "Xvfb already running"
fi

# Check if Wine prefix exists and is properly initialized
if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Wine prefix not found or corrupted, initializing..."
    /home/init-wine.sh
else
    echo "Wine prefix found at: $WINEPREFIX"
fi

# Find BC Server executable
BCSERVER_PATH=$(find /home/bcartifacts -name "Microsoft.Dynamics.Nav.Server.exe" -type f | head -1)
if [ -z "$BCSERVER_PATH" ]; then
    echo "ERROR: BC Server not found in /home/bcartifacts"
    find /home/bcartifacts -name "*.exe" -type f | head -10
    exit 1
fi

echo "Found BC Server at: $BCSERVER_PATH"

# Set up database connection
echo "Setting up database..."
# Note: Assuming SQL Server is available via 'sql' hostname
# This would typically be configured in docker-compose.yml

# Source encryption functions for password handling
source /home/bc-encryption-functions.sh

# Check for existing RSA key first
if [ -f "/home/bcserver/Keys/bc.key" ]; then
    # Check if it's an RSA key (larger than 1000 bytes) or AES key (32 bytes)
    KEY_SIZE=$(stat -c%s "/home/bcserver/Keys/bc.key" 2>/dev/null || echo 0)
    if [ "$KEY_SIZE" -gt 1000 ]; then
        echo "Found existing RSA encryption key (size: $KEY_SIZE bytes)"
        RSA_KEY_EXISTS=true
    else
        echo "Found AES key, but BC requires RSA key for encryption provider"
        RSA_KEY_EXISTS=false
    fi
else
    echo "No encryption key found, generating AES key for future use"
    bc_ensure_encryption_key "/home/bcserver/Keys" "bc.key"
    RSA_KEY_EXISTS=false
fi

# NOTE: BC uses two types of encryption:
# 1. RSA encryption for the LocalKeyFile provider (managed by BC internally)
# 2. AES encryption for password protection (what we implemented)
# If RSA key exists, BC can use ProtectedDatabasePassword
# Otherwise, we use plain passwords

# Create CustomSettings.config from the template file
if [ -f "/home/CustomSettings.config" ]; then
    echo "Creating CustomSettings.config from template file..."
    
    # For now, use plain password until RSA encryption is properly configured
    # TODO: Implement proper RSA key generation for BC's encryption provider
    sed "s/\${SA_PASSWORD}/$SA_PASSWORD/g" /home/CustomSettings.config > /home/bcserver/CustomSettings.config
    
    # Remove any ProtectedDatabasePassword entries and use plain DatabasePassword
    sed -i 's/<add key="ProtectedDatabasePassword".*/<add key="DatabasePassword" value="'"$SA_PASSWORD"'" \/>/' /home/bcserver/CustomSettings.config
    
    echo "CustomSettings.config created with plain password (temporary solution)"
    
    # Also copy to the BC Server directory to override the default
    BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
    cp /home/bcserver/CustomSettings.config "$BCSERVER_DIR/CustomSettings.config"
    echo "Copied CustomSettings.config to BC Server directory"
else
    echo "WARNING: CustomSettings.config template not found at /home/CustomSettings.config"
    # Remove any problematic settings from the default config
    BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
    if [ -f "$BCSERVER_DIR/CustomSettings.config" ]; then
        echo "Fixing default CustomSettings.config..."
        # Remove UnsupportedLanguageIds which can cause issues
        sed -i '/<add key="UnsupportedLanguageIds"/d' "$BCSERVER_DIR/CustomSettings.config"
        echo "Removed UnsupportedLanguageIds from default config"
    fi
fi

# Copy configuration and key files to Wine prefix (BC4Ubuntu approach)
echo "Copying configuration files to Wine prefix..."
BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
WINE_BC_DIR="$BCSERVER_DIR"
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/230/Server/Keys"

if [ -f "/home/bcserver/CustomSettings.config" ]; then
    cp "/home/bcserver/CustomSettings.config" "$WINE_BC_DIR/"
fi

if [ -f "/home/bcserver/Keys/bc.key" ]; then
    cp "/home/bcserver/Keys/bc.key" "$WINE_BC_DIR/Secret.key"
    cp "/home/bcserver/Keys/bc.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/230/Server/Keys/bc.key"
else
    echo "WARNING: Encryption key not found"
fi

# Verify Wine environment
echo "Wine environment:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  WINEARCH: $WINEARCH"
wine --version

# Change to BC Server directory
cd "$BCSERVER_DIR"

# Database setup (optional)
# This section handles database restoration if a backup is found
DB_BAK=$(find /home/bcartifacts -name "*.bak" -type f | head -1)
if [ -n "$DB_BAK" ]; then
    echo "Found database backup: $DB_BAK"
    # Note: Database restoration would typically be handled by SQL Server container
    # This is just a placeholder for the logic
    echo "Database restoration should be handled by SQL Server setup"
fi

# Start BC Server with Wine
echo "Starting BC Server with Wine..."
echo "Command: wine $BCSERVER_PATH /console"
echo ""

# Execute BC Server
# The custom Wine build handles all locale/culture issues internally
exec wine "$BCSERVER_PATH" /console