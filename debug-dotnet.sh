#!/bin/bash

echo "Debugging .NET installation in Wine..."

# Set Wine environment variables
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

echo "Wine prefix: $WINEPREFIX"

if [ ! -d "$WINEPREFIX" ]; then
    echo "ERROR: Wine prefix not found at $WINEPREFIX"
    exit 1
fi

echo ""
echo "=== Wine Version ==="
wine --version

echo ""
echo "=== .NET Installation Directories ==="
echo "Checking for .NET installations..."
ls -la "$WINEPREFIX/drive_c/Program Files/" | grep -i dotnet || echo "No dotnet directory found"
ls -la "$WINEPREFIX/drive_c/Program Files/dotnet/" 2>/dev/null || echo ".NET directory not accessible"

echo ""
echo "=== Windows Directory ==="
ls -la "$WINEPREFIX/drive_c/windows/Microsoft.NET/" 2>/dev/null || echo "Microsoft.NET directory not found"

echo ""
echo "=== Registry Check ==="
echo "Checking .NET registry entries..."
wine reg query "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\.NETFramework" 2>/dev/null || echo ".NET Framework registry not found"

echo ""
echo "=== Try .NET Command ==="
echo "Attempting to run dotnet command..."
wine cmd /c "dotnet --version" 2>/dev/null || echo "dotnet command not available"

echo ""
echo "=== Wine Registry .NET Entries ==="
wine reg query "HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Updates" /s | grep -i "net" | head -10 || echo "No .NET update entries found"

echo ""
echo "Debug complete."
