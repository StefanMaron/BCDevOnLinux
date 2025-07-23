#!/bin/bash

set -e

echo "Starting BC Server using BC4Ubuntu approach..."

# Set Wine environment variables following BC4Ubuntu methodology
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"
export WINE_SKIP_GECKO_INSTALLATION=1
export WINE_SKIP_MONO_INSTALLATION=1

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

# Extract Service Tier files if needed (following BC4Ubuntu approach)
BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
if [ ! -f "$BCSERVER_DIR/Microsoft.Dynamics.Nav.Server.exe" ]; then
    echo "Extracting BC Service Tier files..."
    cd "$BCSERVER_DIR"
    # The artifacts should already be extracted by BcContainerHelper
fi

# Setup database connection
echo "Setting up database..."
# Note: Assuming SQL Server is available via 'sql' hostname
# This would typically be configured in docker-compose.yml

# Generate encryption key if it doesn't exist
if [ ! -f "/home/bcserver/Keys/bc.key" ]; then
    echo "Generating encryption key..."
    pwsh /home/create-encryption-key.ps1
fi

# Create CustomSettings.config from the template file
if [ -f "/home/CustomSettings.config" ]; then
    echo "Creating CustomSettings.config from template file..."
    # Copy the template and substitute the SA_PASSWORD placeholder
    sed "s/\${SA_PASSWORD}/$SA_PASSWORD/g" /home/CustomSettings.config > /home/bcserver/CustomSettings.config
    echo "CustomSettings.config created with substituted password"
else
    echo "WARNING: CustomSettings.config template not found at /home/CustomSettings.config"
fi

# Copy configuration and key files to Wine prefix (BC4Ubuntu approach)
echo "Copying configuration files to Wine prefix..."
WINE_BC_DIR="$BCSERVER_DIR"
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/230/Server/Keys"

if [ -f "/home/bcserver/CustomSettings.config" ]; then
    cp "/home/bcserver/CustomSettings.config" "$WINE_BC_DIR/"
fi

if [ -f "/home/bcserver/Keys/bc.key" ]; then
    cp "/home/bcserver/Keys/bc.key" "$WINE_BC_DIR/Secret.key"
    cp "/home/bcserver/Keys/bc.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/230/Server/Keys/bc.key"
fi

# Start BC Server with Wine (BC4Ubuntu approach)
echo "Starting BC Server with Wine..."
cd "$BCSERVER_DIR"

# Check if BC Server requires .NET 8.0 by looking at the runtime config
if [ -f "Microsoft.Dynamics.Nav.Server.runtimeconfig.json" ]; then
    echo "BC Server requires .NET runtime. Checking availability..."
    
    # Try to start BC Server - if it fails due to missing .NET, we'll provide helpful guidance
    echo "Attempting to start BC Server..."
    echo "If this fails with 'You must install or update .NET', run:"
    echo "  docker exec -it <container_name> /home/install-dotnet8-hosting.sh"
    echo ""
fi

# Use the BC4Ubuntu command structure
WINEPREFIX="$WINEPREFIX" wine "$BCSERVER_PATH" /console

# Create database
/opt/mssql-tools18/bin/sqlcmd -S sql -U sa -P "$SA_PASSWORD" -Q "CREATE DATABASE [CRONUS];" -C -N 2>/dev/null || true

# Setup encryption key and config (same as above)
[ ! -f "/home/bcserver/Keys/BC210.key" ] && pwsh /home/create-encryption-key.ps1

if [ -f "/home/bcserver/CustomSettings.config.template" ]; then
    pwsh -Command "
        \$key = [System.IO.File]::ReadAllBytes('/home/bcserver/Keys/BC210.key');
        \$aes = [System.Security.Cryptography.Aes]::Create();
        \$aes.Key = \$key;
        \$aes.GenerateIV();
        \$passwordBytes = [System.Text.Encoding]::UTF8.GetBytes('$SA_PASSWORD');
        \$encryptor = \$aes.CreateEncryptor();
        \$encryptedPassword = \$encryptor.TransformFinalBlock(\$passwordBytes, 0, \$passwordBytes.Length);
        \$encryptedPasswordBase64 = [Convert]::ToBase64String(\$aes.IV + \$encryptedPassword);
        \$configContent = Get-Content '/home/bcserver/CustomSettings.config.template' -Raw;
        \$configContent = \$configContent -replace 'PLACEHOLDER_PASSWORD', \$encryptedPasswordBase64;
        \$configContent | Out-File -FilePath '/home/bcserver/CustomSettings.config' -Encoding utf8;
    "
fi

# Start BC Server with Wine
BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
cd "$BCSERVER_DIR"
echo "Starting BC Server with Wine..."
exec wine "$BCSERVER_PATH" /console

