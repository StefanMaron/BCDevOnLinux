#!/bin/bash

# Script to run Business Central Server in console mode
# Usage: ./run-bc-console.sh

echo "Starting Business Central Server in console mode..."

# Set Wine environment
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Dynamically detect BC version
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260")
echo "Detected BC version: $BC_VERSION"

# Wine debug settings - adjust as needed
# export WINEDEBUG="-all"  # Minimal output
export WINEDEBUG="+http,+winhttp,+wininet,+httpapi,+advapi,-thread,-combase,-ntdll"  # HTTP debugging
# export WINEDEBUG="+httpapi"  # Just HTTP API debugging

# Ensure we're in the BC Service directory
cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service" || {
    echo "Error: BC Service directory not found!"
    exit 1
}

# Check if config file exists
if [ ! -f "Microsoft.Dynamics.Nav.Server.dll.config" ]; then
    echo "Error: Microsoft.Dynamics.Nav.Server.dll.config not found!"
    exit 1
fi

# Function to extract a setting value from CustomSettings.config
get_setting_value() {
    local key="$1"
    local config_file="$2"
    grep "key=\"$key\"" "$config_file" | sed -n 's/.*value="\([^"]*\)".*/\1/p'
}

# Display key settings from CustomSettings.config
echo ""
echo "=============================================="
echo "BC Server Configuration Summary"
echo "=============================================="

CONFIG_FILE="CustomSettings.config"

if [ -f "$CONFIG_FILE" ]; then
    echo ""
    echo "Database Settings:"
    echo "  Server:         $(get_setting_value "DatabaseServer" "$CONFIG_FILE")"
    echo "  Instance:       $(get_setting_value "DatabaseInstance" "$CONFIG_FILE")"
    echo "  Database:       $(get_setting_value "DatabaseName" "$CONFIG_FILE")"
    echo "  User:           $(get_setting_value "DatabaseUserName" "$CONFIG_FILE")"

    echo ""
    echo "Server Settings:"
    echo "  Instance Name:  $(get_setting_value "ServerInstance" "$CONFIG_FILE")"
    echo "  Auth Type:      $(get_setting_value "ClientServicesCredentialType" "$CONFIG_FILE")"

    echo ""
    echo "Service Ports:"
    echo "  Client:         $(get_setting_value "ClientServicesPort" "$CONFIG_FILE")"
    echo "  SOAP:           $(get_setting_value "SOAPServicesPort" "$CONFIG_FILE")"
    echo "  OData:          $(get_setting_value "ODataServicesPort" "$CONFIG_FILE")"
    echo "  Management:     $(get_setting_value "ManagementServicesPort" "$CONFIG_FILE")"
    echo "  Developer:      $(get_setting_value "DeveloperServicesPort" "$CONFIG_FILE")"

    echo ""
    echo "Services Enabled:"
    echo "  Client Services:      $(get_setting_value "ClientServicesEnabled" "$CONFIG_FILE")"
    echo "  SOAP Services:        $(get_setting_value "SOAPServicesEnabled" "$CONFIG_FILE")"
    echo "  OData Services:       $(get_setting_value "ODataServicesEnabled" "$CONFIG_FILE")"
    echo "  Developer Services:   $(get_setting_value "DeveloperServicesEnabled" "$CONFIG_FILE")"
    echo "  Management Services:  $(get_setting_value "ManagementServicesEnabled" "$CONFIG_FILE")"

    echo ""
    echo "=============================================="
else
    echo "WARNING: CustomSettings.config not found in current directory"
fi

echo ""
read -p "Start BC Server with these settings? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Server startup cancelled by user."
    exit 0
fi

# Run BC Server with instance name $BC
echo "Running: wine Microsoft.Dynamics.Nav.Server.exe \$BC /config Microsoft.Dynamics.Nav.Server.dll.config /console"
echo ""
echo "Look for 'BUSINESS CENTRAL SERVER BINDING ON PORT' messages..."
echo "Press Ctrl+C to stop the server"
echo ""

# Run BC Server
wine Microsoft.Dynamics.Nav.Server.exe '$BC' /config Microsoft.Dynamics.Nav.Server.dll.config /console 2>&1 | tee /tmp/bc_console.log