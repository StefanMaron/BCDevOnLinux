#!/bin/bash

# Simple script to run BC Server
# Place in container at /home/run-bc.sh

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export WINEDEBUG="-all"  # Change to "+httpapi" for HTTP debugging

# Dynamically detect BC version
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260")
echo "Detected BC version: $BC_VERSION"

cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service"

echo "Starting BC Server..."
wine Microsoft.Dynamics.Nav.Server.exe '$BusinessCentral'"$BC_VERSION" /config Microsoft.Dynamics.Nav.Server.dll.config /console