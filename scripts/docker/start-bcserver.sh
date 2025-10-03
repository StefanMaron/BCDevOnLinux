#!/bin/bash

set -e

echo "Starting BC Server..."

# Status file for tracking initialization
STATUS_FILE="/home/bc-init-status.txt"
echo "Starting BC Server initialization at $(date)" > "$STATUS_FILE"

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
export WINEDEBUG="-all"

# Standard locale settings (no special workarounds needed with custom Wine)
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

# Set DOTNET_ROOT for BC Server v26 to find .NET 8.0
export DOTNET_ROOT="C:\\Program Files\\dotnet"

# Also set in Wine registry for BC to find it
wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" /v DOTNET_ROOT /t REG_SZ /d "C:\\Program Files\\dotnet" /f 2>/dev/null || true
# Add dotnet to PATH in Wine registry
wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" /v Path /t REG_EXPAND_SZ /d "%SystemRoot%\\system32;%SystemRoot%;%SystemRoot%\\system32\\wbem;%SystemRoot%\\system32\\WindowsPowershell\\v1.0;C:\\Program Files\\dotnet" /f 2>/dev/null || true

# Ensure virtual display is running
if ! pgrep -f "Xvfb :0" > /dev/null; then
    echo "Starting Xvfb for Wine..."
    # Clean up any stale lock files first
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
    export XKB_DEFAULT_LAYOUT=us
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
    sleep 2
else
    echo "Xvfb already running"
fi

# Check if Wine prefix exists and has all required components
if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Wine prefix not found or corrupted, initializing..."
    echo "STATUS: Initializing Wine prefix..." >> "$STATUS_FILE"
    /home/scripts/wine/init-wine.sh
    echo "STATUS: Wine prefix initialization completed" >> "$STATUS_FILE"
else
    echo "Wine prefix found at: $WINEPREFIX"
    echo "Verifying required .NET components are installed..."
    echo "STATUS: Checking .NET components..." >> "$STATUS_FILE"
fi

# BC Server path in standard Wine Program Files location
BCSERVER_PATH="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service/Microsoft.Dynamics.Nav.Server.exe"
if [ ! -f "$BCSERVER_PATH" ]; then
    echo "BC Server not found in Wine prefix, installing from MSI..."
    echo "STATUS: Installing BC Server from MSI..." >> "$STATUS_FILE"

    # Install BC Server using file copy (MSI doesn't work unattended in Wine)
    if [ -f "/home/scripts/bc/install-bc-files.sh" ]; then
        bash /home/scripts/bc/install-bc-files.sh
        echo "STATUS: BC Server file installation completed" >> "$STATUS_FILE"
    else
        echo "ERROR: install-bc-files.sh not found!"
        exit 1
    fi

    # Verify installation - check for critical files
    if [ ! -f "$BCSERVER_PATH" ]; then
        echo "ERROR: BC Server installation failed - executable not found"
        exit 1
    fi

    # Also verify critical runtime files exist
    if [ ! -f "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service/Microsoft.Dynamics.Nav.Server.deps.json" ]; then
        echo "ERROR: deps.json file missing after installation"
        exit 1
    fi

    if [ ! -f "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service/Microsoft.Dynamics.Nav.Server.runtimeconfig.json" ]; then
        echo "ERROR: runtimeconfig.json file missing after installation"
        exit 1
    fi

    echo "BC Server installation verified with all critical files"
fi

echo "Found BC Server at: $BCSERVER_PATH"


# Copy configuration and key files to Wine prefix (BC4Ubuntu approach)
echo "Copying configuration files to Wine prefix..."
BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys"

# FORCE OVERWRITE the config file - this is critical!
if [ -f "/home/bcserver/CustomSettings.config" ]; then
    echo "Forcing copy of CustomSettings.config from /home/bcserver/"
    cp -f "/home/bcserver/CustomSettings.config" "$BCSERVER_DIR/CustomSettings.config"
    echo "Config copied and overwritten successfully"
elif [ -f "/home/CustomSettings.config" ]; then
    echo "Forcing copy of CustomSettings.config from /home/"
    cp -f "/home/CustomSettings.config" "$BCSERVER_DIR/CustomSettings.config"
    echo "Config copied and overwritten successfully"
    # Verify the copy worked
    echo "Verifying DatabaseInstance setting in copied file:"
    grep "DatabaseInstance" "$BCSERVER_DIR/CustomSettings.config" | head -1
else
    echo "ERROR: CustomSettings.config not found in /home/bcserver/ or /home/"
    echo "BC will use the default config from artifacts (which has DatabaseInstance=MSSQLSERVER)"
    exit 1
fi

# Check for encryption keys - prioritize /home/bcserver/ location
if [ -f "/home/bcserver/Keys/bc.key" ]; then
    echo "Using bc.key from /home/bcserver/Keys/"
    # Copy to ProgramData locations
    cp "/home/bcserver/Keys/bc.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/DynamicsNAV90.key"
    
    echo "Encryption keys copied to all required locations"
elif [ -f "/home/config/secret.key" ]; then
    echo "Using RSA key from /home/config/secret.key (fallback location)"
    # Copy to all required locations in Wine prefix
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/BusinessCentral260.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/BC.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/DynamicsNAV90.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/bc.key"
    
    echo "RSA encryption keys copied to all required locations"
else
    echo "ERROR: No encryption key found!"
    echo "Expected locations (in priority order):"
    echo "  1. /home/bcserver/secret.key (RSA key)"
    echo "  2. /home/bcserver/Keys/bc.key"
    echo "  3. /home/config/secret.key (fallback)"
fi

# Verify Wine environment
echo "Wine environment:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  WINEARCH: $WINEARCH"
echo "  WINEDEBUG: $WINEDEBUG"
wine --version

# Change to BC Server directory
cd "$BCSERVER_DIR"

# Start BC Server with Wine
echo "Starting BC Server with Wine..."

echo "Command: wine $BCSERVER_PATH /console"
echo ""

# Execute BC Server
# The custom Wine build handles all locale/culture issues internally
echo "STATUS: Starting BC Server..." >> "$STATUS_FILE"

# Start BC Server in foreground (required for Wine console processes)
echo "Starting BC Server..."
wine Microsoft.Dynamics.Nav.Server.exe '$BusinessCentral260' /config Microsoft.Dynamics.Nav.Server.dll.config /console 2>&1 | tee /var/log/bc-server.log

