#!/bin/bash
set -e

echo "Installing .NET 8.0.18 Hosting Bundle to match working VM..."

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64

cd /tmp

# Download the hosting bundle which contains both runtimes
echo "Downloading .NET 8.0.18 hosting bundle..."
HOSTING_URL="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.18/dotnet-hosting-8.0.18-win.exe"
rm -f dotnet-hosting-8.0.18-win.exe
wget --progress=bar:force "$HOSTING_URL" -O dotnet-hosting-8.0.18-win.exe

# Install the hosting bundle using Wine
echo "Installing .NET 8.0.18 Hosting Bundle with Wine..."
echo "This installs:"
echo "  - ASP.NET Core 8.0.18 Runtime"
echo "  - .NET Core 8.0.18 Runtime"
echo "  - ASP.NET Core Module for IIS"

# Run the installer with quiet mode
# /quiet - quiet install with no UI
# /install - install the product
# /norestart - don't restart after install
wine dotnet-hosting-8.0.18-win.exe /quiet /install /norestart 2>&1 | grep -v "^wine:" || true

echo ""
echo "Waiting for installation to complete..."
sleep 5

# Verify installation
echo ""
echo "Verifying installed runtimes..."
wine dotnet --list-runtimes 2>/dev/null | grep -E "Microsoft\.(AspNetCore|NETCore|WindowsDesktop)\.App" || echo "Note: Wine dotnet command may not show all runtimes"

# List the actual directories to confirm
DOTNET_DIR="$WINEPREFIX/drive_c/Program Files/dotnet"
if [ -d "$DOTNET_DIR/shared" ]; then
    echo ""
    echo "Installed runtime directories:"
    if [ -d "$DOTNET_DIR/shared/Microsoft.AspNetCore.App" ]; then
        ls -la "$DOTNET_DIR/shared/Microsoft.AspNetCore.App/" | grep "8.0" || echo "No ASP.NET Core 8.0 versions found"
    fi
    if [ -d "$DOTNET_DIR/shared/Microsoft.NETCore.App" ]; then
        ls -la "$DOTNET_DIR/shared/Microsoft.NETCore.App/" | grep "8.0" || echo "No .NET Core 8.0 versions found"
    fi
fi

# Clean up temp files
echo ""
echo "Cleaning up temporary files..."
rm -f dotnet-hosting-8.0.18-win.exe
rm -rf hosting-extract

echo ""
echo ".NET 8.0.18 Hosting Bundle installation completed!"
echo "This includes ASP.NET Core Runtime, .NET Runtime, and IIS support modules."