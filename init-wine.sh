#!/bin/bash

set -e

echo "Initializing Wine environment using BC4Ubuntu approach..."

# Wine environment variables following BC4Ubuntu
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
# export WINE_SKIP_GECKO_INSTALLATION=1
# export WINE_SKIP_MONO_INSTALLATION=1
export DISPLAY=":0"

# Virtual display will be started only when needed for specific Wine operations

# remove wine prefix folder 
# Uncomment the next line if you want to reset the Wine prefix
# rm -rf "$WINEPREFIX" || true

# Create Wine prefix directory
echo "Creating Wine prefix directory..."
# mkdir -p "$WINEPREFIX"


# # Initialize Wine prefix - this is the key step from BC4Ubuntu
# echo "Initializing Wine prefix..."
winecfg /v win11

# # Wait for Wine to settle
# sleep 5

# # Install .NET Desktop Runtime 6.0 (BC4Ubuntu approach)
# echo "Installing .NET Desktop Runtime 6.0..."
# winetricks prefix=bc1 -q dotnetdesktop6

# Now install .NET 8.0 runtime and ASP.NET Core 8.0 which BC Server v26 needs
echo "Installing .NET 8.0 runtime for BC Server v26..."
cd /tmp

# Download and install ASP.NET Core Runtime 8.0.18 directly from Microsoft
echo "Downloading ASP.NET Core Runtime 8.0.18..."
ASPNET_INSTALLER="dotnet-hosting-8.0.18-win.exe"
ASPNET_URL="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.18/${ASPNET_INSTALLER}"

# Download the installer
wget -O "/tmp/${ASPNET_INSTALLER}" "${ASPNET_URL}" || {
    echo "Failed to download ASP.NET Core Runtime 8.0.18"
    echo "You may need to install it manually later"
    exit 1
}

echo "Installing ASP.NET Core Runtime 8.0.18 via Wine..."

# Start virtual display for the installer
echo "Starting virtual display for ASP.NET installer..."
# Clean up any stale lock files first
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
XVFB_PID=$!
sleep 3

# Run the installer
WINEPREFIX="$WINEPREFIX" wine "/tmp/${ASPNET_INSTALLER}" /quiet /install /norestart

# Stop virtual display
echo "Stopping virtual display..."
kill $XVFB_PID 2>/dev/null || true
# Clean up display files
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# Clean up the installer
rm -f "/tmp/${ASPNET_INSTALLER}"

echo "ASP.NET Core Runtime 8.0.18 installation completed"

# Following BC4Ubuntu approach - install .NET Framework 4.8 first
echo "Installing .NET Framework 4.8 (following BC4Ubuntu approach)..."
winetricks prefix=bc1 -q dotnet48

# Set Windows version to Windows 10 for better compatibility
echo "Setting Windows version to Windows 10..."
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v "Version" /t REG_SZ /d "win10" /f

# Configure Wine registry settings for BC Server compatibility
echo "Configuring Wine registry for BC Server..."
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\.NETFramework" /v "InstallRoot" /t REG_SZ /d "C:\\Windows\\Microsoft.NET\\Framework64\\" /f
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\.NETFramework\\v4.0.30319" /v "SchUseStrongCrypto" /t REG_DWORD /d 1 /f

# Disable problematic graphics features for headless operation
echo "Configuring graphics settings for headless operation..."
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v "DirectDrawRenderer" /t REG_SZ /d "opengl" /f
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v "UseGLSL" /t REG_SZ /d "disabled" /f
WINEPREFIX="$WINEPREFIX" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v "UseVulkan" /t REG_SZ /d "disabled" /f

echo "Wine prefix initialization completed successfully"
echo "Wine prefix location: $WINEPREFIX"

# Verify .NET installation
echo "Verifying .NET installation..."
WINEPREFIX="$WINEPREFIX" wine cmd /c "dotnet --version" || echo "Note: .NET CLI may not be available through Wine"

echo "Wine initialization completed successfully. Virtual display was used only during ASP.NET installation."
