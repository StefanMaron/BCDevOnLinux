#!/bin/bash

set -e

echo "Starting BC Server..."

# Status file for tracking initialization
STATUS_FILE="/home/bc-init-status.txt"
echo "Starting BC Server initialization at $(date)" > "$STATUS_FILE"

# Historical Note:
# This script previously had multiple variants (workaround and final-fix) to handle
# Wine culture/locale issues that caused BC to fail with "'en-US' is not a valid language code".
# These workarounds are no longer needed since we now use a custom Wine build with locale fixes.
# The old scripts are preserved in legacy/culture-workarounds/ for reference.

# Set Wine environment variables following BC4Ubuntu methodology
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"
export WINE_SKIP_GECKO_INSTALLATION=1
export WINE_SKIP_MONO_INSTALLATION=1
export WINEDEBUG="+http,+err,+warn,+trace,+fixme,-thread,-combase,-ntdll,-heap,-bcrypt,-wtsapi,-seh"

# Standard locale settings (no special workarounds needed with custom Wine)
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

# Set DOTNET_ROOT for BC Server v26 to find .NET 8.0
export DOTNET_ROOT="C:\\Program Files\\dotnet"

# Also set in Wine registry for BC to find it
wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" /v DOTNET_ROOT /t REG_SZ /d "C:\\Program Files\\dotnet" /f 2>/dev/null || true
# Add dotnet to PATH in Wine registry
wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" /v Path /t REG_EXPAND_SZ /d "%SystemRoot%\\system32;%SystemRoot%;%SystemRoot%\\system32\\wbem;%SystemRoot%\\system32\\WindowsPowershell\\v1.0;C:\\Program Files\\dotnet" /f 2>/dev/null || true

# Ensure virtual display is running
if ! pgrep -f "Xvfb :0" > /dev/null; then
    echo "Starting Xvfb for Wine..."
    # Clean up any stale lock files first
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX &
    sleep 2
else
    echo "Xvfb already running"
fi

# Source the .NET component check function
if [ -f "/home/check-wine-dotnet.sh" ]; then
    source /home/check-wine-dotnet.sh
fi

# Check if Wine prefix exists and has all required components
if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Wine prefix not found or corrupted, initializing..."
    echo "STATUS: Initializing Wine prefix..." >> "$STATUS_FILE"
    /home/init-wine.sh
    echo "STATUS: Wine prefix initialization completed" >> "$STATUS_FILE"
else
    echo "Wine prefix found at: $WINEPREFIX"
    echo "Verifying required .NET components are installed..."
    echo "STATUS: Checking .NET components..." >> "$STATUS_FILE"
    
    # Check if function is available
    if type check_wine_dotnet_components &>/dev/null; then
        if ! check_wine_dotnet_components "$WINEPREFIX"; then
            echo "Required .NET components are missing!"
            echo "Running .NET component installation..."
            echo "STATUS: Installing .NET components - this may take 5-10 minutes..." >> "$STATUS_FILE"
            echo "STATUS: Installing .NET Framework 4.8..." >> "$STATUS_FILE"
            
            # Run the install script
            if [ -f "/home/install-dotnet-components.sh" ]; then
                /home/install-dotnet-components.sh
            else
                echo "WARNING: install-dotnet-components.sh not found, running init-wine.sh instead"
                /home/init-wine.sh
            fi
            
            echo "STATUS: .NET installation completed, verifying..." >> "$STATUS_FILE"
            
            # Verify installation succeeded
            if ! check_wine_dotnet_components "$WINEPREFIX"; then
                echo "ERROR: .NET component installation failed!"
                echo "BC Server may not start correctly without required .NET components"
                echo "STATUS: ERROR - .NET installation verification failed" >> "$STATUS_FILE"
                # Continue anyway, but warn the user
            else
                echo "STATUS: .NET components successfully installed" >> "$STATUS_FILE"
            fi
        else
            echo "All required .NET components are present"
            echo "STATUS: All .NET components verified" >> "$STATUS_FILE"
        fi
    else
        echo "WARNING: .NET component check function not available, skipping verification"
        echo "STATUS: WARNING - Cannot verify .NET components" >> "$STATUS_FILE"
    fi
fi

# BC Server path in standard Wine Program Files location
BCSERVER_PATH="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service/Microsoft.Dynamics.Nav.Server.exe"
if [ ! -f "$BCSERVER_PATH" ]; then
    echo "BC Server not found in Wine prefix, checking artifacts..."
    
    # Look for BC Server in artifacts
    BC_ARTIFACTS_SERVICE="/home/bcartifacts/ServiceTier/program files/Microsoft Dynamics NAV/260/Service"
    if [ -d "$BC_ARTIFACTS_SERVICE" ] && [ -f "$BC_ARTIFACTS_SERVICE/Microsoft.Dynamics.Nav.Server.exe" ]; then
        echo "Found BC Server in artifacts, copying to Wine prefix..."
        
        # Create target directory
        WINE_BC_DIR="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service"
        mkdir -p "$WINE_BC_DIR"
        
        # Copy all service files
        echo "Copying BC Service files from artifacts to Wine prefix..."
        cp -r "$BC_ARTIFACTS_SERVICE"/* "$WINE_BC_DIR/"
        
        # Create hard link for config file (MSI behavior)
        if [ ! -f "$WINE_BC_DIR/Microsoft.Dynamics.Nav.Server.exe.config" ]; then
            cd "$WINE_BC_DIR"
            ln "Microsoft.Dynamics.Nav.Server.dll.config" "Microsoft.Dynamics.Nav.Server.exe.config" 2>/dev/null || \
                cp "Microsoft.Dynamics.Nav.Server.dll.config" "Microsoft.Dynamics.Nav.Server.exe.config"
            cd - > /dev/null
        fi
        
        echo "BC Server files copied successfully"
    else
        echo "ERROR: BC Server not found in artifacts at: $BC_ARTIFACTS_SERVICE"
        echo "Available artifact structure:"
        find /home/bcartifacts -name "Microsoft.Dynamics.Nav.Server.exe" -type f | head -5
        exit 1
    fi
fi

echo "Found BC Server at: $BCSERVER_PATH"


# Copy configuration and key files to Wine prefix (BC4Ubuntu approach)
echo "Copying configuration files to Wine prefix..."
BCSERVER_DIR=$(dirname "$BCSERVER_PATH")
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys"

# FORCE OVERWRITE the config file - this is critical!
if [ -f "/home/bcserver/CustomSettings.config" ]; then
    echo "Forcing copy of CustomSettings.config from /home/bcserver/"
    cp -f "/home/bcserver/CustomSettings.config" "$BCSERVER_DIR/CustomSettings.config"
    echo "Config copied and overwritten successfully"
elif [ -f "/home/CustomSettings.config" ]; then
    echo "Forcing copy of CustomSettings.config from /home/"
    cp -f "/home/CustomSettings.config" "$BCSERVER_DIR/CustomSettings.config"
    echo "Config copied and overwritten successfully"
    # Verify the copy worked
    echo "Verifying DatabaseInstance setting in copied file:"
    grep "DatabaseInstance" "$BCSERVER_DIR/CustomSettings.config" | head -1
else
    echo "ERROR: CustomSettings.config not found in /home/bcserver/ or /home/"
    echo "BC will use the default config from artifacts (which has DatabaseInstance=MSSQLSERVER)"
    exit 1
fi

# Check for encryption keys - prioritize /home/bcserver/ location
if [ -f "/home/bcserver/Keys/bc.key" ]; then
    echo "Using bc.key from /home/bcserver/Keys/"
    # Copy to ProgramData locations
    cp "/home/bcserver/Keys/bc.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/DynamicsNAV90.key"
    
    echo "Encryption keys copied to all required locations"
elif [ -f "/home/secret.key" ]; then
    echo "Using RSA key from /home/secret.key (fallback location)"
    # Copy to all required locations in Wine prefix
    cp "/home/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/BusinessCentral260.key"
    cp "/home/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/BC.key"
    cp "/home/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/DynamicsNAV90.key"
    cp "/home/secret.key" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys/bc.key"
    
    echo "RSA encryption keys copied to all required locations"
else
    echo "ERROR: No encryption key found!"
    echo "Expected locations (in priority order):"
    echo "  1. /home/bcserver/secret.key (RSA key)"
    echo "  2. /home/bcserver/Keys/bc.key"
    echo "  3. /home/secret.key (fallback)"
fi

# Verify Wine environment
echo "Wine environment:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  WINEARCH: $WINEARCH"
wine --version

# Change to BC Server directory
cd "$BCSERVER_DIR"

# Start BC Server with Wine
echo "Starting BC Server with Wine..."

# When ReportingServiceIsSideService is false, BC Server manages the reporting service internally
# So we don't start it separately
echo "BC Server will manage reporting service internally (ReportingServiceIsSideService=false)"

echo "Command: wine $BCSERVER_PATH /console"
echo ""

# Execute BC Server
# The custom Wine build handles all locale/culture issues internally
echo "STATUS: Starting BC Server..." >> "$STATUS_FILE"
echo "STATUS: BC initialization complete at $(date)" >> "$STATUS_FILE"
exec wine "$BCSERVER_PATH" /console