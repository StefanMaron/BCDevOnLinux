#!/bin/bash

set -e

echo "Starting Business Central Container using BC4Ubuntu approach..."

# Set default environment variables if not provided
export SA_PASSWORD=${SA_PASSWORD:-"YourPassword123"}

# Setup BC encryption keys with RSA support
if [ ! -f "/home/bcserver/Keys/bc.key" ]; then
    echo "Setting up BC encryption with RSA key generation..."
    
    # Create keys directory if it doesn't exist
    mkdir -p "/home/bcserver/Keys"
    
    # Try to generate RSA key in XML format (BC standard)
    if command -v pwsh &> /dev/null; then
        echo "Generating RSA encryption key in BC-compatible XML format..."
        if pwsh -File "/home/create-rsa-encryption-key.ps1" -KeyPath "/home/bcserver/Keys/bc.key"; then
            echo "✅ RSA encryption key generated successfully"
            
            # Verify the key was created in correct format
            if [ -f "/home/bcserver/Keys/bc.key" ]; then
                # Source detection functions to verify
                source /home/bc-rsa-encryption-functions.sh
                KEY_TYPE=$(bc_detect_key_type "/home/bcserver/Keys/bc.key")
                echo "Generated key type: $KEY_TYPE"
                
                if [ "$KEY_TYPE" = "RSA" ]; then
                    echo "✅ RSA key verified - BC-compatible XML format"
                else
                    echo "⚠️  Warning: Generated key type is $KEY_TYPE, expected RSA"
                fi
            fi
        else
            echo "❌ Failed to generate RSA key with PowerShell"
            echo "Falling back to AES encryption..."
            
            # Fallback to AES key generation
            source /home/bc-rsa-encryption-functions.sh
            if bc_ensure_encryption_key "/home/bcserver/Keys" "bc.key"; then
                echo "✅ AES encryption key generated (fallback)"
            else
                echo "❌ Failed to generate any encryption key"
                exit 1
            fi
        fi
    else
        echo "PowerShell not available for RSA key generation"
        echo "Generating AES encryption key instead..."
        
        # Fallback to AES key generation
        source /home/bc-rsa-encryption-functions.sh
        if bc_ensure_encryption_key "/home/bcserver/Keys" "bc.key"; then
            echo "✅ AES encryption key generated"
        else
            echo "❌ Failed to generate encryption key"
            exit 1
        fi
    fi
else
    echo "Encryption key already exists, skipping generation"
    
    # Check if existing key needs upgrade to XML format
    source /home/bc-rsa-encryption-functions.sh
    KEY_TYPE=$(bc_detect_key_type "/home/bcserver/Keys/bc.key")
    echo "Existing key type: $KEY_TYPE"
    
    if [ "$KEY_TYPE" = "LEGACY_RSA" ]; then
        echo "⚠️  Legacy RSA key detected - will be upgraded during BC Server startup"
    elif [ "$KEY_TYPE" = "RSA" ]; then
        echo "✅ Modern RSA key in XML format detected"
    elif [ "$KEY_TYPE" = "AES" ]; then
        echo "✅ AES key detected"
    else
        echo "⚠️  Unknown key format: $KEY_TYPE"
    fi
fi

# Check if this is first run and initialize Wine if needed
if [ ! -f "/home/.wine-initialized" ]; then
    echo "First run detected, initializing Wine environment..."
    /home/init-wine.sh
    touch /home/.wine-initialized
    echo "Wine initialization completed"
fi

# Restore database if needed
export PATH="$PATH:/opt/mssql-tools18/bin"
if command -v sqlcmd >/dev/null 2>&1; then
    echo "Checking database..."
    /home/restore-database.sh
else
    echo "sqlcmd not found, skipping database restore"
    echo "Database must be restored manually"
fi

# Check if BC_AUTOSTART is set to false
if [ "${BC_AUTOSTART}" = "false" ]; then
    echo "BC_AUTOSTART is set to false. Container will stay running without starting BC Server."
    echo "To start BC Server manually, run:"
    echo "  /home/start-bcserver.sh"
    echo ""
    echo "Container is ready for debugging..."
    # Keep container running
    tail -f /dev/null
else
    # Start the BC server
    echo "Starting BC Server..."
    # Note: The custom Wine build includes locale fixes, eliminating the need for
    # the previous workaround scripts (now archived in legacy/culture-workarounds/)
    exec /home/start-bcserver.sh
fi
