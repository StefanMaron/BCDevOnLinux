#!/bin/bash
# Script to display SQL settings from BC CustomSettings.config

# Source Wine environment
if [ -f /home/scripts/wine/wine-env.sh ]; then
    source /home/scripts/wine/wine-env.sh >/dev/null 2>&1
fi

# Dynamically detect BC version
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260")
echo "Detected BC version: $BC_VERSION"

# Define config path
CONFIG_PATH="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service/CustomSettings.config"

echo "BC SQL Configuration Settings"
echo "============================"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: CustomSettings.config not found at:"
    echo "  $CONFIG_PATH"
    echo ""
    echo "Checking alternative locations..."

    # Check if it exists in home directories
    if [ -f "/home/bcserver/CustomSettings.config" ]; then
        echo "Found config in /home/bcserver/"
        CONFIG_PATH="/home/bcserver/CustomSettings.config"
    elif [ -f "/home/CustomSettings.config" ]; then
        echo "Found config in /home/"
        CONFIG_PATH="/home/CustomSettings.config"
    else
        echo "No CustomSettings.config found!"
        exit 1
    fi
fi

echo "Reading from: $CONFIG_PATH"
echo ""

# Function to extract setting value
get_setting() {
    local key="$1"
    local value=$(grep -E "key=\"$key\"" "$CONFIG_PATH" | sed -E 's/.*value="([^"]*)".*/\1/g')
    echo "$value"
}

# Extract SQL-related settings
echo "Database Connection Settings:"
echo "----------------------------"
echo "DatabaseServer:     $(get_setting "DatabaseServer")"
echo "DatabaseInstance:   $(get_setting "DatabaseInstance")"
echo "DatabaseName:       $(get_setting "DatabaseName")"
echo "DatabaseUserName:   $(get_setting "DatabaseUserName")"
echo ""

echo "Authentication Settings:"
echo "-----------------------"
echo "SQLCommandTimeout:  $(get_setting "SQLCommandTimeout")"
echo "SqlConnectionTimeout: $(get_setting "SqlConnectionTimeout")"
echo ""

# Check for encrypted password
ENCRYPTED_PASS=$(get_setting "ProtectedDatabasePassword")
if [ -n "$ENCRYPTED_PASS" ]; then
    echo "ProtectedDatabasePassword: [ENCRYPTED - ${#ENCRYPTED_PASS} characters]"
    echo "First 50 chars: ${ENCRYPTED_PASS:0:50}..."
else
    echo "ProtectedDatabasePassword: [NOT SET]"
fi

# Check for plain text password (shouldn't be used in production)
PLAIN_PASS=$(get_setting "DatabasePassword")
if [ -n "$PLAIN_PASS" ]; then
    echo "DatabasePassword: [SET - ${#PLAIN_PASS} characters]"
else
    echo "DatabasePassword: [NOT SET]"
fi

echo ""
echo "Additional SQL Settings:"
echo "-----------------------"
echo "EnableSqlConnectionEncryption: $(get_setting "EnableSqlConnectionEncryption")"
echo "TrustSQLServerCertificate: $(get_setting "TrustSQLServerCertificate")"
echo ""

# Show full connection string that BC would use
echo "Constructed Connection String:"
echo "-----------------------------"
SERVER=$(get_setting "DatabaseServer")
INSTANCE=$(get_setting "DatabaseInstance")
DATABASE=$(get_setting "DatabaseName")
USERNAME=$(get_setting "DatabaseUserName")

if [ -n "$INSTANCE" ] && [ "$INSTANCE" != "" ]; then
    FULL_SERVER="$SERVER\\$INSTANCE"
else
    FULL_SERVER="$SERVER"
fi

echo "Server=$FULL_SERVER;Database=$DATABASE;"
if [ -n "$USERNAME" ]; then
    echo "User ID=$USERNAME;[Password]"
else
    echo "Integrated Security=true"
fi

echo ""
echo "Encryption Key Check:"
echo "--------------------"
KEY_PATH="$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys"
if [ -d "$KEY_PATH" ]; then
    echo "Keys directory exists. Contents:"
    ls -la "$KEY_PATH" 2>/dev/null | grep -E "\.(key|txt)$" || echo "  No key files found"
else
    echo "Keys directory not found at: $KEY_PATH"
fi