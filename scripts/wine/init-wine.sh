#!/bin/bash

set -e

echo "Initializing Wine environment using BC4Ubuntu approach..."

# Ensure en_US.UTF-8 locale is generated
echo "Generating en_US.UTF-8 locale..."
locale-gen en_US.UTF-8 || echo "locale-gen failed, continuing..."
update-locale LANG=en_US.UTF-8 || echo "update-locale failed, continuing..."

# Wine environment variables following BC4Ubuntu
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
# export WINE_SKIP_GECKO_INSTALLATION=1
# export WINE_SKIP_MONO_INSTALLATION=1
export DISPLAY=":0"
export WINEDEBUG=-winediag

# Virtual display will be started only when needed for specific Wine operations

# remove wine prefix folder 
# Uncomment the next line if you want to reset the Wine prefix
# rm -rf "$WINEPREFIX" || true

# Create Wine prefix directory
echo "Creating Wine prefix directory..."
mkdir -p "$WINEPREFIX"


# # Initialize Wine prefix - this is the key step from BC4Ubuntu
# echo "Initializing Wine prefix..."
winecfg /v win11

# # Wait for Wine to settle
# sleep 5

# # Install .NET Desktop Runtime 6.0 (BC4Ubuntu approach)
# echo "Installing .NET Desktop Runtime 6.0..."
# winetricks prefix=bc1 -q dotnetdesktop6

# Start virtual display for .NET installation
echo "Starting virtual display for .NET installation..."
# Clean up any stale lock files first
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
XVFB_PID=$!
sleep 3

# Install .NET Framework 4.8 first (BC Server v26 needs this for main server)
echo "Installing .NET Framework 4.8..."
winetricks prefix=bc1 -q dotnet48

# Wait for .NET Framework installation to settle
sleep 5

# Install .NET Desktop Runtime 8.0 directly (BC Server v26 needs this)
echo "Installing .NET Desktop Runtime 8.0..."
cd /tmp
wget -q "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.18/windowsdesktop-runtime-8.0.18-win-x64.exe" || {
    echo "Failed to download .NET Desktop Runtime 8.0"
    exit 1
}
wine windowsdesktop-runtime-8.0.18-win-x64.exe /quiet /install /norestart
rm -f windowsdesktop-runtime-8.0.18-win-x64.exe
echo ".NET Desktop Runtime 8.0 installation completed"

# Now install ASP.NET Core 8.0 hosting bundle which BC Server v26 also needs
echo "Installing ASP.NET Core 8.0 hosting bundle for BC Server v26..."
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

# Run the installer
WINEPREFIX="$WINEPREFIX" wine "/tmp/${ASPNET_INSTALLER}" /quiet /install /norestart

# Stop virtual display (moved to end of script)

# Clean up the installer
rm -f "/tmp/${ASPNET_INSTALLER}"

echo "ASP.NET Core Runtime 8.0.18 installation completed"

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

echo "Wine initialization completed successfully."

# Stop virtual display
echo "Stopping virtual display..."
kill $XVFB_PID 2>/dev/null || true
# Clean up display files
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# Apply Wine culture fixes if the script exists
if [ -f "/home/fix-wine-cultures.sh" ]; then
    echo "Applying Wine culture fixes..."
    /home/fix-wine-cultures.sh
fi
