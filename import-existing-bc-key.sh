#!/bin/bash
# Script to import an existing BC encryption key

set -e

KEY_SOURCE="$1"
BC_VERSION="${2:-260}"  # Default to BC 260

if [ -z "$KEY_SOURCE" ]; then
    echo "Usage: $0 <path-to-existing-key-file> [bc-version]"
    echo "Example: $0 /path/to/existing/bc.key 260"
    exit 1
fi

if [ ! -f "$KEY_SOURCE" ]; then
    echo "ERROR: Key file not found: $KEY_SOURCE"
    exit 1
fi

echo "Importing BC encryption key from: $KEY_SOURCE"

# Create keys directory
mkdir -p /home/bcserver/Keys

# Copy the key with various names BC might expect
cp "$KEY_SOURCE" /home/bcserver/Keys/bc.key
cp "$KEY_SOURCE" /home/bcserver/Keys/Secret.key
cp "$KEY_SOURCE" /home/bcserver/Keys/BC${BC_VERSION}.key

# Set proper permissions
chmod 600 /home/bcserver/Keys/*.key

echo "Key imported successfully. Created:"
ls -la /home/bcserver/Keys/

echo ""
echo "Next steps:"
echo "1. Copy the key into the BC container:"
echo "   docker cp /home/bcserver/Keys/bc.key bcdevonlinux-bc-1:/home/bcserver/Keys/"
echo "   docker cp /home/bcserver/Keys/Secret.key bcdevonlinux-bc-1:/home/bcserver/Keys/"
echo "   docker cp /home/bcserver/Keys/BC${BC_VERSION}.key bcdevonlinux-bc-1:/home/bcserver/Keys/"
echo ""
echo "2. Also copy to BC service directory inside container:"
echo "   docker compose -f compose-wine-custom.yml exec bc cp /home/bcserver/Keys/*.key \"/home/bcartifacts/platform/ServiceTier/program files/Microsoft Dynamics NAV/${BC_VERSION}/Service/\""
echo ""
echo "3. If you know the password was encrypted with this key, you can use ProtectedDatabasePassword in the config"