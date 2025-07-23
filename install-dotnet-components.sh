#!/bin/bash

set -e

echo "Installing .NET components for BC Server following BC4Ubuntu approach..."

# Set Wine environment variables
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Ensure Wine prefix exists
if [ ! -d "$WINEPREFIX" ]; then
    echo "ERROR: Wine prefix not found. Run init-wine.sh first."
    exit 1
fi

# Download and install ASP.NET Core runtime (as per BC4Ubuntu)
echo "Downloading ASP.NET Core 6.0 runtime..."
cd /tmp

# Download the specific version used in BC4Ubuntu
wget -q https://download.visualstudio.microsoft.com/download/pr/321a2352-a7aa-492a-bd0d-491a963de7cc/6d17be7b07b8bc22db898db0ff37a5cc/dotnet-hosting-6.0.14-win.exe -O dotnet-hosting-6.0.14-win.exe

if [ -f "dotnet-hosting-6.0.14-win.exe" ]; then
    echo "Installing ASP.NET Core hosting bundle in Wine..."
    
    # Use Wine uninstaller GUI for installation (BC4Ubuntu approach)
    echo "Starting Wine uninstaller for .NET installation..."
    echo "Install the ASP.NET Core hosting bundle when the GUI appears..."
    
    WINEPREFIX="$WINEPREFIX" wine uninstaller &
    
    # Copy the installer to Wine's temp directory for easy access
    cp dotnet-hosting-6.0.14-win.exe "$WINEPREFIX/drive_c/users/root/Temp/"
    
    echo "ASP.NET Core installer copied to Wine temp directory"
    echo "Please install it manually through the Wine uninstaller GUI"
    
    wait
    
    rm -f dotnet-hosting-6.0.14-win.exe
else
    echo "ERROR: Failed to download ASP.NET Core installer"
    exit 1
fi

echo ".NET components installation completed"
