#!/bin/bash

set -e

echo "Initializing Wine environment using BC4Ubuntu approach..."

# Base image has dynamic linker already configured for Wine
# Do not run ldconfig as it may interfere with base image configuration

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

# Wine library paths are already configured by base image
# Do not override LD_LIBRARY_PATH or WINEDLLPATH

# Virtual display will be started only when needed for specific Wine operations

# remove wine prefix folder 
# Uncomment the next line if you want to reset the Wine prefix
# rm -rf "$WINEPREFIX" || true

# Create Wine prefix directory
echo "Creating Wine prefix directory..."
mkdir -p "$WINEPREFIX"


# Debug: Check environment variables
echo "Checking Wine environment variables:"
echo "  WINEDLLPATH: $WINEDLLPATH"
echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "  PATH: $PATH"
echo "  Wine location: $(which wine)"
echo "  Wine version: $(wine --version || echo 'Wine not working')"

# Initialize Wine prefix using wineboot (more reliable than winecfg)
echo "Initializing Wine prefix with wineboot..."
wineboot --init

# Wait for Wine to settle
sleep 5

# Configure Windows version after initialization
echo "Setting Windows version to Windows 11..."
wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v "Version" /t REG_SZ /d "win11" /f

# # Install .NET Desktop Runtime 6.0 (BC4Ubuntu approach)
# echo "Installing .NET Desktop Runtime 6.0..."
# winetricks prefix=bc1 -q dotnetdesktop6

# Start virtual display for .NET installation
echo "Starting virtual display for .NET installation..."
# Clean up any stale lock files first
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
export XKB_DEFAULT_LAYOUT=us
Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
XVFB_PID=$!
sleep 3

# Note: .NET 8 installation can be handled by:
# - /home/scripts/utils/update-dotnet-runtimes.sh for .NET 8.0.18 Hosting Bundle (recommended for BC v26)
# - /usr/local/bin/wine-init-runtime.sh for minimal Wine setup
# - /usr/local/bin/wine-init-full.sh for .NET 8 runtime installation
# echo "Installing .NET 8.0.18 Hosting Bundle for BC v26..."
# if [ -f "/home/scripts/utils/update-dotnet-runtimes.sh" ]; then
#     /home/scripts/utils/update-dotnet-runtimes.sh
# else
#     echo "Note: .NET installation handled by base image runtime scripts"
# fi
echo "Note: .NET 8 should be pre-installed in base image"

# .NET Framework 4.8 installation disabled per user request
# if [ ! -d "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319" ]; then
#     echo "Installing .NET Framework 4.8..."
#     WINEDLLPATH="/usr/local/lib/wine/x86_64-unix:/usr/local/lib/wine/x86_64-windows" \
#     LD_LIBRARY_PATH="/usr/local/lib/wine/x86_64-unix:/usr/local/lib:${LD_LIBRARY_PATH}" \
#     winetricks prefix=bc1 -q dotnet48
#     echo ".NET Framework 4.8 installation completed"
# else
#     echo ".NET Framework 4.8 already installed"
# fi
echo "Skipping .NET Framework 4.8 installation (disabled)"

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
if [ -f "/home/scripts/wine/fix-wine-cultures.sh" ]; then
    echo "Applying Wine culture fixes..."
    /home/scripts/wine/fix-wine-cultures.sh
fi
