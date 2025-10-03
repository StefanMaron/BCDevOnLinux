#!/bin/bash

# Simple script to run BC Server
# Place in container at /home/run-bc.sh

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export WINEDEBUG="-all"  # Change to "+httpapi" for HTTP debugging

cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service"

echo "Starting BC Server..."
wine Microsoft.Dynamics.Nav.Server.exe '$BusinessCentral260' /config Microsoft.Dynamics.Nav.Server.dll.config /console