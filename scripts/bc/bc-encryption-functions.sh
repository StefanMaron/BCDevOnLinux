#!/bin/bash
# bc-encryption-functions.sh - Shared functions for BC encryption
# This file should be sourced by scripts that need encryption functionality

# Function to encrypt database password using BC encryption key
bc_encrypt_password() {
    local password="$1"
    local key_file="${2:-/home/bcserver/Keys/bc.key}"
    
    if [ ! -f "$key_file" ]; then
        echo "ERROR: Encryption key not found: $key_file" >&2
        return 1
    fi
    
    # Read key as hex
    local key_hex=$(xxd -p -c 32 "$key_file" 2>/dev/null)
    if [ -z "$key_hex" ]; then
        echo "ERROR: Failed to read encryption key" >&2
        return 1
    fi
    
    # Generate random IV
    local iv_hex=$(openssl rand -hex 16 2>/dev/null)
    if [ -z "$iv_hex" ]; then
        echo "ERROR: Failed to generate IV" >&2
        return 1
    fi
    
    # Encrypt password using AES-256-CBC
    local encrypted_hex=$(echo -n "$password" | \
        openssl enc -aes-256-cbc -e -K "$key_hex" -iv "$iv_hex" 2>/dev/null | \
        xxd -p -c 256 2>/dev/null)
    
    if [ -z "$encrypted_hex" ]; then
        echo "ERROR: Failed to encrypt password" >&2
        return 1
    fi
    
    # Create temporary file for binary concatenation
    local temp_file=$(mktemp)
    echo -n "$iv_hex" | xxd -r -p > "$temp_file" 2>/dev/null
    echo -n "$encrypted_hex" | xxd -r -p >> "$temp_file" 2>/dev/null
    
    # Base64 encode the result
    local protected_password=$(base64 -w 0 < "$temp_file" 2>/dev/null)
    rm -f "$temp_file"
    
    if [ -z "$protected_password" ]; then
        echo "ERROR: Failed to encode encrypted password" >&2
        return 1
    fi
    
    echo "$protected_password"
    return 0
}

# Function to update CustomSettings.config with encrypted password
bc_update_config_password() {
    local config_file="$1"
    local password="$2"
    local key_file="${3:-/home/bcserver/Keys/bc.key}"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi
    
    # Encrypt the password
    local encrypted_password=$(bc_encrypt_password "$password" "$key_file")
    if [ -z "$encrypted_password" ]; then
        echo "ERROR: Failed to encrypt password for config" >&2
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Update the config file
    # First, remove any existing DatabasePassword line
    sed '/DatabasePassword/d' "$config_file" > "$temp_file"
    
    # Then add the ProtectedDatabasePassword after DatabaseUserName
    awk -v enc="$encrypted_password" '
        /DatabaseUserName/ {
            print
            print "  <add key=\"ProtectedDatabasePassword\" value=\"" enc "\" />"
            next
        }
        { print }
    ' "$temp_file" > "${temp_file}.2"
    
    # Move the result back
    mv "${temp_file}.2" "$config_file"
    rm -f "$temp_file"
    
    echo "Config updated with encrypted password"
    return 0
}

# Function to generate encryption key if it doesn't exist
bc_ensure_encryption_key() {
    local key_dir="${1:-/home/bcserver/Keys}"
    local key_name="${2:-bc.key}"
    local key_path="$key_dir/$key_name"
    
    if [ ! -f "$key_path" ]; then
        echo "Creating BC encryption key at $key_path..."
        mkdir -p "$key_dir"
        openssl rand -out "$key_path" 32
        chmod 600 "$key_path"
        
        # Create compatibility copies
        for version in BC210 BC220 BC230 BC240; do
            if [ ! -f "$key_dir/${version}.key" ]; then
                cp "$key_path" "$key_dir/${version}.key"
                chmod 600 "$key_dir/${version}.key"
            fi
        done
        
        # Create Secret.key copy
        if [ ! -f "$key_dir/Secret.key" ]; then
            cp "$key_path" "$key_dir/Secret.key"
            chmod 600 "$key_dir/Secret.key"
        fi
        
        echo "Encryption key created successfully"
    fi
    
    return 0
}