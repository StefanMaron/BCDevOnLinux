#!/bin/bash

# Script to run Business Central Server in console mode
# Usage: ./run-bc-console.sh

echo "Starting Business Central Server in console mode..."

# Set Wine environment
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Wine debug settings - adjust as needed
# export WINEDEBUG="-all"  # Minimal output
export WINEDEBUG="+http,+winhttp,+wininet,+httpapi,+advapi,-thread,-combase,-ntdll"  # HTTP debugging
# export WINEDEBUG="+httpapi"  # Just HTTP API debugging

# Ensure we're in the BC Service directory
cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service" || {
    echo "Error: BC Service directory not found!"
    exit 1
}

# Check if config file exists
if [ ! -f "Microsoft.Dynamics.Nav.Server.dll.config" ]; then
    echo "Error: Microsoft.Dynamics.Nav.Server.dll.config not found!"
    exit 1
fi

# Run BC Server with instance name $BusinessCentral260
echo "Running: wine Microsoft.Dynamics.Nav.Server.exe \$BusinessCentral260 /config Microsoft.Dynamics.Nav.Server.dll.config /console"
echo ""
echo "Look for 'BUSINESS CENTRAL SERVER BINDING ON PORT' messages..."
echo "Press Ctrl+C to stop the server"
echo ""

# Run BC Server
wine Microsoft.Dynamics.Nav.Server.exe '$BusinessCentral260' /config Microsoft.Dynamics.Nav.Server.dll.config /console 2>&1 | tee /tmp/bc_console.log