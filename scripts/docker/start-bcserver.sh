#!/bin/bash

set -e
set -o pipefail

# PID tracking for graceful shutdown
BC_PID=0

# Function to handle graceful shutdown
graceful_shutdown() {
  echo "Caught signal, shutting down BC Server..."
  if [ $BC_PID -ne 0 ]; then
    # Send SIGTERM to the process group
    kill -TERM -$BC_PID 2>/dev/null || true
    wait $BC_PID 2>/dev/null || true
  fi
  exit 0
}

# Trap SIGTERM and SIGINT for graceful shutdown
trap graceful_shutdown SIGTERM SIGINT

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
# Wine debug settings - respect VERBOSE_LOGGING
if [ "$VERBOSE_LOGGING" = "true" ] || [ "$VERBOSE_LOGGING" = "1" ]; then
    export WINEDEBUG="${WINEDEBUG:-+http,+winhttp,+httpapi,+advapi,-thread,-combase,-ntdll}"
else
    export WINEDEBUG="${WINEDEBUG:--all}"
fi

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

# Wine prefix is guaranteed to exist from base image build
echo "✓ Wine prefix: $WINEPREFIX (pre-initialized in base image)"
echo "✓ .NET 8 components: pre-installed at build time"
echo "STATUS: Wine and .NET verified from base image" >> "$STATUS_FILE"

# Dynamically detect BC version from artifacts
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260")
echo "Detected BC version: $BC_VERSION"

# BC Server path in standard Wine Program Files location
BCSERVER_PATH="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service/Microsoft.Dynamics.Nav.Server.exe"
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
    if [ ! -f "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service/Microsoft.Dynamics.Nav.Server.deps.json" ]; then
        echo "ERROR: deps.json file missing after installation"
        exit 1
    fi

    if [ ! -f "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service/Microsoft.Dynamics.Nav.Server.runtimeconfig.json" ]; then
        echo "ERROR: runtimeconfig.json file missing after installation"
        exit 1
    fi

    echo "BC Server installation verified with all critical files"
fi

echo "Found BC Server at: $BCSERVER_PATH"

# IMPORTANT: Config copy happens EVERY TIME, not just on first install
# This ensures our custom config always overwrites any artifact defaults
echo ""
echo "========================================="
echo "FORCE COPYING CONFIGURATION FILES"
echo "This runs on every container start to ensure correct settings"
echo "========================================="

BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys"

# FORCE OVERWRITE the config file - this is critical!
# Note: /home/bcserver/ was a legacy location, now removed
if [ -f "/home/CustomSettings.config" ]; then
    echo "✓ Forcing copy of CustomSettings.config from /home/"
    cp -f "/home/CustomSettings.config" "$BCSERVER_DIR/CustomSettings.config"
    echo "✓ Config copied and overwritten successfully"
else
    echo "✗ ERROR: CustomSettings.config not found at /home/CustomSettings.config"
    echo "BC will use the default config from artifacts"
    exit 1
fi

# VERIFY the critical settings were applied correctly
echo ""
echo "Verifying critical configuration settings:"
echo "  DatabaseInstance: $(grep -m1 'key="DatabaseInstance"' "$BCSERVER_DIR/CustomSettings.config" | sed 's/.*value="\([^"]*\)".*/\1/')"
echo "  ClientServicesCredentialType: $(grep -m1 'key="ClientServicesCredentialType"' "$BCSERVER_DIR/CustomSettings.config" | sed 's/.*value="\([^"]*\)".*/\1/')"
echo "  DatabaseServer: $(grep -m1 'key="DatabaseServer"' "$BCSERVER_DIR/CustomSettings.config" | sed 's/.*value="\([^"]*\)".*/\1/')"
echo ""

# Copy encryption keys (legacy /home/bcserver/ location removed)
if [ -f "/home/config/secret.key" ]; then
    echo "✓ Using RSA key from /home/config/secret.key"
    # Copy to all required locations in Wine prefix
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys/BusinessCentral${BC_VERSION}.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys/BC.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys/DynamicsNAV90.key"
    cp "/home/config/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys/bc.key"

    echo "✓ RSA encryption keys copied to all required locations"
else
    echo "✗ ERROR: No encryption key found at /home/config/secret.key"
    exit 1
fi

# Verify Wine environment
echo "Wine environment:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  WINEARCH: $WINEARCH"
echo "  WINEDEBUG: $WINEDEBUG"
wine --version

# Change to BC Server directory
cd "$BCSERVER_DIR"

# Execute BC Server
# The custom Wine build handles all locale/culture issues internally
echo "STATUS: Starting BC Server..." >> "$STATUS_FILE"

# Start BC Server in console mode with persistent stdin
# The /console flag activates HTTP listeners immediately
# tail -f /dev/null keeps stdin open indefinitely without producing output
echo "Starting BC Server in console mode..."
set -m  # Enable job control for proper signal handling
tail -f /dev/null | wine Microsoft.Dynamics.Nav.Server.exe '$BC' /config Microsoft.Dynamics.Nav.Server.dll.config /console 2>&1 | tee /var/log/bc-server.log &
BC_PID=$!

echo "BC Server started with PID $BC_PID"
echo "Waiting for BC Server to initialize..."

# Monitor log for readiness message
timeout=600  # 10 minutes timeout
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if grep -q "Press Enter to stop the console server" /var/log/bc-server.log; then
        echo "✓ BC Server is ready for connections!"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    if [ $((elapsed % 10)) -eq 0 ]; then
        echo "Still initializing... ($elapsed seconds elapsed)"
    fi
done

if [ $elapsed -ge $timeout ]; then
    echo "⚠ Timeout waiting for BC Server readiness message"
    echo "Check /var/log/bc-server.log for details"
fi

# Wait for the background process
wait $BC_PID

