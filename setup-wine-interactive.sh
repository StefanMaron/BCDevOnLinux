#!/bin/bash

set -e

echo "BC4Ubuntu Wine Setup - Final Configuration Steps"
echo "================================================"

# Set Wine environment variables
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

echo "Wine prefix location: $WINEPREFIX"

# Check if Wine prefix exists
if [ ! -d "$WINEPREFIX" ]; then
    echo "Wine prefix not found. Run the container first to initialize Wine."
    exit 1
fi

echo "Current Wine prefix contents:"
ls -la "$WINEPREFIX/drive_c/" || echo "Wine prefix not accessible"

# Install PowerShell 5.1 using winetricks (BC4Ubuntu approach)
echo ""
echo "Step 1: Install PowerShell 5.1"
echo "================================"
echo "Starting PowerShell Core for winetricks installation..."
echo "In the PowerShell prompt, type: winetricks ps51"
echo "Then press Enter and follow the installation prompts."
echo ""

WINEPREFIX="$WINEPREFIX" wine powershell

echo ""
echo "Step 2: Check Wine Registry Configuration"
echo "========================================"
WINEPREFIX="$WINEPREFIX" wine regedit &
echo "Registry editor started. You can verify Wine configuration."
echo "Close the registry editor when done."
wait

echo ""
echo "Step 3: Manual .NET Installation"
echo "==============================="
echo "Run the .NET installer script if needed:"
echo "./install-dotnet-components.sh"

echo ""
echo "Step 4: Start Wine Command Prompt"
echo "================================="
echo "Starting Wine command prompt for final testing..."
WINEPREFIX="$WINEPREFIX" wine cmd

echo ""
echo "Setup completed. Your Wine environment is ready for BC Server."
echo "To start BC Server, use: ./start-bcserver.sh"
