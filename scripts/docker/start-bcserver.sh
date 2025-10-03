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
#export WINEDEBUG="-all"
export WINEDEBUG="+http,+winhttp,+httpapi,+advapi,-thread,-combase,-ntdll"  # debugging

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

# Register BC Server as a Windows service in Wine (if not already registered)
echo "Checking BC Server service registration..."
if ! wine reg query 'HKLM\SYSTEM\CurrentControlSet\Services\MicrosoftDynamicsNavServer$BusinessCentral260' 2>/dev/null | grep -q "ImagePath"; then
    echo "Registering BC Server as a Windows service..."

    # Create service registry key
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /f 2>/dev/null

    # Set service configuration matching the VM setup
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v DisplayName /t REG_SZ /d "Microsoft Dynamics 365 Business Central Server [BusinessCentral260]" /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v Description /t REG_SZ /d "Service handling requests to the Microsoft Dynamics 365 Business Central application" /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v ImagePath /t REG_SZ /d "C:\\Program Files\\Microsoft Dynamics NAV\\260\\Service\\Microsoft.Dynamics.Nav.Server.exe \$BusinessCentral260 /config \"C:\\Program Files\\Microsoft Dynamics NAV\\260\\Service\\Microsoft.Dynamics.Nav.Server.dll.config\"" /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v ObjectName /t REG_SZ /d "NT AUTHORITY\\NETWORK SERVICE" /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v Start /t REG_DWORD /d 2 /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v Type /t REG_DWORD /d 16 /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v ErrorControl /t REG_DWORD /d 0 /f 2>/dev/null
    wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\MicrosoftDynamicsNavServer\$BusinessCentral260" /v DependOnService /t REG_MULTI_SZ /d "HTTP" /f 2>/dev/null

    echo "BC Server service registered successfully"
else
    echo "BC Server service already registered"
fi

./home/scripts/bc/import-license.sh

# Start Wine Service Control Manager
# This is the Windows service manager that will auto-start BC Server (Start=2 in registry)
echo "Starting Wine Service Control Manager..."
echo "STATUS: Starting Wine services.exe..." >> "$STATUS_FILE"

# Start services.exe in background (this is PID 1's job in the container)
wine services.exe 2>&1 | tee -a /var/log/bc-server.log &
SERVICES_PID=$!

echo "Waiting for services.exe to initialize..."
sleep 5

# Verify services.exe is running
if ! kill -0 $SERVICES_PID 2>/dev/null; then
    echo "ERROR: Wine services.exe failed to start"
    exit 1
fi

echo "Wine Service Control Manager started (PID: $SERVICES_PID)"
echo "STATUS: services.exe running, waiting for BC Server auto-start..." >> "$STATUS_FILE"

# Wait for BC Server to auto-start (Start=2 in registry means AUTO_START)
echo "Waiting for BC Server service to auto-start (1-2 minutes)..."
for i in {1..60}; do
    if pgrep -f "Microsoft.Dynamics.Nav.Server.exe" > /dev/null; then
        BC_PID=$(pgrep -f "Microsoft.Dynamics.Nav.Server.exe")
        echo "✓ BC Server service auto-started successfully (PID: $BC_PID)"
        echo "STATUS: BC Server running on PID $BC_PID" >> "$STATUS_FILE"
        break
    fi
    sleep 2
done

# Verify BC Server is running
if ! pgrep -f "Microsoft.Dynamics.Nav.Server.exe" > /dev/null; then
    echo "ERROR: BC Server did not auto-start within 2 minutes"
    echo "Checking service registration..."
    wine reg query 'HKLM\SYSTEM\CurrentControlSet\Services\MicrosoftDynamicsNavServer$BusinessCentral260' 2>&1 | head -10
    echo "Checking logs..."
    tail -50 /var/log/bc-server.log
    exit 1
fi

BC_PID=$(pgrep -f "Microsoft.Dynamics.Nav.Server.exe")
echo "BC Server is running as Windows service (matching VM setup)"
echo "Monitoring BC Server process..."

# Monitor the BC Server process - if it exits, container should exit
while kill -0 $BC_PID 2>/dev/null; do
    sleep 5
done

echo "BC Server process has exited"
exit 1

