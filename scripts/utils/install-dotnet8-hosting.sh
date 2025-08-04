#!/bin/bash

set -e

echo "Manual .NET 8.0 Installation for BC Server"
echo "=========================================="

# Set Wine environment variables
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Ensure Wine prefix exists
if [ ! -d "$WINEPREFIX" ]; then
    echo "ERROR: Wine prefix not found. Run init-wine.sh first."
    exit 1
fi

echo "Current Wine prefix: $WINEPREFIX"

# Check current .NET installations
echo ""
echo "Checking current .NET installations..."
ls -la "$WINEPREFIX/drive_c/Program Files/" | grep -i dotnet || echo "No dotnet directory found"

echo ""
echo "=== MANUAL INSTALLATION REQUIRED ==="
echo ""
echo "BC Server v26 requires .NET 8.0 and ASP.NET Core 8.0."
echo "The automatic download URLs have changed. Please:"
echo ""
echo "1. Go to: https://dotnet.microsoft.com/download/dotnet/8.0"
echo "2. Download the 'Hosting Bundle' for Windows x64"
echo "3. Copy the installer into the container:"
echo "   docker cp <hosting-bundle.exe> <container>:/tmp/"
echo "4. Run the installer in Wine:"
echo "   WINEPREFIX=$WINEPREFIX wine /tmp/<hosting-bundle.exe>"
echo ""
echo "Alternatively, try the interactive installer below..."

echo ""
echo "Starting Wine uninstaller for manual installation..."
echo "When the GUI opens:"
echo "1. Click 'Install...'"
echo "2. Browse to the .NET installer you downloaded"
echo "3. Follow the installation wizard"

# Start Wine uninstaller for manual installation
WINEPREFIX="$WINEPREFIX" wine uninstaller

echo ""
echo "After installation, verify with:"
echo "ls -la '$WINEPREFIX/drive_c/Program Files/dotnet/'"
