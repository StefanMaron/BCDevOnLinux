#!/bin/bash
# bc-rsa-encryption-functions.sh - Enhanced encryption functions for BC with RSA support
# This file provides functions for both AES and RSA encryption modes

# Source the original functions
source /home/bc-encryption-functions.sh

# Function to check if a key file is RSA or AES
bc_detect_key_type() {
    local key_file="${1:-/home/bcserver/Keys/bc.key}"
    
    echo "DEBUG: Checking key file: $key_file" >&2
    
    if [ ! -f "$key_file" ]; then
        echo "DEBUG: File does not exist" >&2
        echo "NONE"
        return 1
    fi
    
    echo "DEBUG: File exists, reading content..." >&2
    
    # Get file size first
    local key_size
    key_size=$(stat -c%s "$key_file" 2>/dev/null || echo 0)
    echo "DEBUG: File size: $key_size bytes" >&2
    
    # Read first line safely
    local first_line
    first_line=$(head -n 1 "$key_file" 2>/dev/null | tr -d '\0' | head -c 100 2>/dev/null || echo "")
    
    echo "DEBUG: First line (first 100 chars): '$first_line'" >&2
    
    # Check for XML RSA format (new format)
    if [[ "$first_line" == *"<RSAKeyValue>"* ]]; then
        echo "DEBUG: Detected RSA XML format (new)" >&2
        echo "RSA"
        return 0
    fi
    
    # Check for AES format (32 bytes exactly)
    if [ "$key_size" -eq 32 ]; then
        echo "DEBUG: Detected AES format (32 bytes)" >&2
        echo "AES"
        return 0
    fi
    
    # Check for old encrypted RSA format (JSON wrapper)
    if [[ "$first_line" == "{"* ]]; then
        echo "DEBUG: Detected legacy RSA format (JSON)" >&2
        echo "LEGACY_RSA"
        return 0
    fi
    
    # Check for old encrypted RSA format (binary with salt/IV)
    if [ "$key_size" -gt 100 ] && [ "$key_size" -lt 10000 ]; then
        # This might be an old encrypted RSA key (binary format)
        # Try to detect if this looks like AES-encrypted data
        local file_type
        file_type=$(file "$key_file" 2>/dev/null || echo "")
        echo "DEBUG: File type detection: $file_type" >&2
        
        if [[ "$file_type" == *"data"* ]] || [[ "$file_type" == *"binary"* ]]; then
            echo "DEBUG: Detected legacy encrypted RSA format (binary)" >&2
            echo "LEGACY_RSA"
            return 0
        fi
    fi
    
    # If file is not empty but we couldn't identify it
    if [ "$key_size" -gt 0 ]; then
        echo "DEBUG: Unknown format - file has content but doesn't match known patterns" >&2
        echo "UNKNOWN"
        return 1
    fi
    
    # Empty file
    echo "DEBUG: Empty file detected" >&2
    echo "NONE"
    return 1
}

# Function to generate RSA encryption key using PowerShell
bc_generate_rsa_key() {
    local key_dir="${1:-/home/bcserver/Keys}"
    local key_name="${2:-bc.key}"
    local key_path="$key_dir/$key_name"
    local force_flag="${3:-false}"
    
    echo "Generating RSA encryption key for BC LocalKeyFile provider..."
    
    # Create directory if it doesn't exist
    mkdir -p "$key_dir"
    
    # Check if PowerShell is available
    if ! command -v pwsh &> /dev/null; then
        echo "ERROR: PowerShell (pwsh) is required for RSA key generation"
        echo "Install PowerShell Core or use AES encryption instead"
        echo "DEBUG: PowerShell check: $(command -v pwsh 2>&1 || echo 'Command not found')"
        return 1
    fi
    
    echo "DEBUG: PowerShell found: $(pwsh --version 2>&1 || echo 'Version check failed')"
    
    # Run PowerShell script to generate RSA key
    local ps_args=""
    if [ "$force_flag" = "true" ]; then
        ps_args="-Force"
    fi
    
    echo "DEBUG: Executing PowerShell script: pwsh -File /home/create-rsa-encryption-key.ps1 -KeyPath \"$key_path\" $ps_args"
    
    if pwsh -File /home/create-rsa-encryption-key.ps1 -KeyPath "$key_path" $ps_args; then
        echo "RSA key generated successfully at: $key_path"
        
        # Set proper permissions
        chmod 600 "$key_path"
        
        # Create compatibility copies
        if [ ! -f "$key_dir/Secret.key" ]; then
            cp "$key_path" "$key_dir/Secret.key"
            chmod 600 "$key_dir/Secret.key"
        fi
        
        return 0
    else
        echo "ERROR: Failed to generate RSA key"
        return 1
    fi
}

# Function to encrypt database password using RSA key (BC-compatible format)
bc_encrypt_password_rsa() {
    local password="$1"
    local key_file="${2:-/home/bcserver/Keys/bc.key}"
    local verbose="${3:-false}"
    
    if [ ! -f "$key_file" ]; then
        echo "ERROR: RSA key file not found: $key_file" >&2
        return 1
    fi
    
    # Check if PowerShell is available
    if ! command -v pwsh &> /dev/null; then
        echo "ERROR: PowerShell (pwsh) is required for RSA encryption" >&2
        return 1
    fi
    
    # Check if the PowerShell script exists
    local ps_script_name="encrypt-password-with-rsa.ps1"
    local ps_script=""
    
    # Look for the script in common locations
    for location in "/home/$ps_script_name" "/home/stefan/Documents/Repos/community/BCDevOnLinux/$ps_script_name" "$(dirname "$0")/$ps_script_name" "./$ps_script_name"; do
        if [ -f "$location" ]; then
            ps_script="$location"
            break
        fi
    done
    
    if [ -z "$ps_script" ]; then
        echo "ERROR: PowerShell encryption script not found: $ps_script_name" >&2
        echo "Please ensure $ps_script_name is in the same directory or /home/" >&2
        return 1
    fi
    
    # Get password file path
    local password_file=""
    local key_dir=$(dirname "$key_file")
    if [ -f "$key_dir/bc-key-password.txt" ]; then
        password_file="$key_dir/bc-key-password.txt"
    fi
    
    # Build PowerShell command arguments properly escaped
    local ps_cmd="pwsh -File \"$ps_script\" -Password \"$password\" -KeyPath \"$key_file\""
    if [ -n "$password_file" ]; then
        ps_cmd="$ps_cmd -PasswordFile \"$password_file\""
    fi
    if [ "$verbose" = "true" ]; then
        ps_cmd="$ps_cmd -VerboseLogging"
    fi
     # Execute PowerShell script
    local encrypted_password
    local error_output
    if [ "$verbose" = "true" ]; then
        echo "DEBUG: Executing command: $ps_cmd" >&2
        # Capture stderr separately for debugging, but only use stdout for the actual result
        local temp_stderr=$(mktemp)
        encrypted_password=$(eval "$ps_cmd" 2>"$temp_stderr")
        local exit_code=$?
        echo "DEBUG: PowerShell exit code: $exit_code" >&2
        echo "DEBUG: PowerShell output: $encrypted_password" >&2
        if [ -s "$temp_stderr" ]; then
            echo "DEBUG: PowerShell stderr:" >&2
            cat "$temp_stderr" >&2
        fi
        rm -f "$temp_stderr"
    else
        error_output=$(eval "$ps_cmd" 2>&1)
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            encrypted_password="$error_output"
        else
            echo "DEBUG: PowerShell failed with exit code: $exit_code" >&2
            echo "DEBUG: PowerShell error output: $error_output" >&2
        fi
    fi

    if [ $exit_code -eq 0 ] && [ -n "$encrypted_password" ]; then
        echo "$encrypted_password"
        return 0
    else
        echo "ERROR: Failed to encrypt password with RSA key" >&2
        if [ -n "$error_output" ]; then
            echo "PowerShell error details: $error_output" >&2
        fi
        return 1
    fi
}

# Function to update CustomSettings.config for RSA encryption
bc_update_config_rsa() {
    local config_file="$1"
    local password="$2"
    local key_file="${3:-/home/bcserver/Keys/bc.key}"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi
    
    echo "Updating configuration for RSA encryption with ProtectedDatabasePassword..."
    
    # Encrypt the password using RSA key (enable verbose for debugging)
    local encrypted_password
    
    # Check for potential key-password file timestamp mismatch (caching issue)
    if [ -f "$key_file" ] && [ -f "$(dirname "$key_file")/bc-key-password.txt" ]; then
        local key_time=$(stat -c %Y "$key_file" 2>/dev/null || echo 0)
        local password_time=$(stat -c %Y "$(dirname "$key_file")/bc-key-password.txt" 2>/dev/null || echo 0)
        local time_diff=$((key_time - password_time))
        
        if [ ${time_diff#-} -gt 60 ]; then  # Absolute difference > 60 seconds
            echo "WARNING: Key and password files have significant timestamp difference (${time_diff}s)" >&2
            echo "This may indicate a container caching issue. Consider regenerating the RSA key." >&2
        fi
    fi
    
    if encrypted_password=$(bc_encrypt_password_rsa "$password" "$key_file" true); then
        echo "Password encrypted successfully for ProtectedDatabasePassword"
    else
        echo "ERROR: Failed to encrypt password with RSA key" >&2
        echo "This is likely due to key-password mismatch or database key mismatch" >&2
        
        # Check if we should attempt automatic recovery
        if [ "$BC_AUTO_REGENERATE_KEY" = "true" ]; then
            echo "🔄 Auto-regenerating RSA key (BC_AUTO_REGENERATE_KEY=true)..."
            auto_regenerate=true
        else
            echo "💡 You can set BC_AUTO_REGENERATE_KEY=true to auto-regenerate keys in containers"
            read -p "Attempt to regenerate RSA key and replace database key? (y/N): " -r
            auto_regenerate=false
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                auto_regenerate=true
            fi
        fi
        
        if [ "$auto_regenerate" = "true" ]; then
            echo "🔄 Attempting automatic RSA key regeneration..."
            
            if bc_force_regenerate_rsa_key "$(dirname "$key_file")" "$(basename "$key_file")"; then
                echo "✅ RSA key regenerated, retrying password encryption..."
                
                # Retry encryption with new key
                if encrypted_password=$(bc_encrypt_password_rsa "$password" "$key_file" true); then
                    echo "✅ Password encryption successful with new key!"
                else
                    echo "❌ Password encryption still failed after key regeneration"
                    echo "ERROR: Failed to encrypt password, falling back to plain text" >&2
                    sed -i "s/\${SA_PASSWORD}/$password/g" "$config_file"
                    return 1
                fi
            else
                echo "❌ Failed to regenerate RSA key"
                echo "ERROR: Failed to encrypt password, falling back to plain text" >&2
                sed -i "s/\${SA_PASSWORD}/$password/g" "$config_file"
                return 1
            fi
        else
            echo "ERROR: Failed to encrypt password, falling back to plain text" >&2
            sed -i "s/\${SA_PASSWORD}/$password/g" "$config_file"
            return 1
        fi
    fi
    
    # Create temporary file for modifications
    local temp_file=$(mktemp)
    cp "$config_file" "$temp_file"
    
    # Remove any existing password-related settings
    sed -i '/DatabasePassword/d' "$temp_file"
    sed -i '/ProtectedDatabasePassword/d' "$temp_file"
    
    # Add ProtectedDatabasePassword with encrypted value
    # Insert after DatabaseUserName
    awk -v encrypted_pass="$encrypted_password" '
        /DatabaseUserName/ {
            print
            print "  <add key=\"ProtectedDatabasePassword\" value=\"" encrypted_pass "\" />"
            next
        }
        { print }
    ' "$temp_file" > "${temp_file}.2"
    
    # Move the result back
    mv "${temp_file}.2" "$config_file"
    rm -f "$temp_file"
    
    echo "Configuration updated for RSA encryption:"
    echo "  - Using ProtectedDatabasePassword with RSA-encrypted value"
    echo "  - BC Server will decrypt using LocalKeyFile provider"
    
    return 0
}

# Enhanced function to ensure encryption key (with RSA preference)
bc_ensure_encryption_key_enhanced() {
    local key_dir="${1:-/home/bcserver/Keys}"
    local key_name="${2:-bc.key}"
    local key_path="$key_dir/$key_name"
    local prefer_rsa="${3:-true}"
    
    if [ -f "$key_path" ]; then
        local key_type=$(bc_detect_key_type "$key_path")
        echo "Found existing $key_type encryption key at: $key_path"
        return 0
    fi
    
    echo "No encryption key found, generating new key..."
    
    if [ "$prefer_rsa" = "true" ] && command -v pwsh &> /dev/null; then
        echo "Generating RSA key (recommended for BC LocalKeyFile provider)..."
        echo "DEBUG: PowerShell found at: $(which pwsh)"
        echo "DEBUG: Attempting RSA key generation..."
        if bc_generate_rsa_key "$key_dir" "$key_name"; then
            echo "RSA key generation successful"
            return 0
        else
            echo "RSA key generation failed, falling back to AES..."
            echo "DEBUG: Check PowerShell scripts and permissions"
        fi
    else
        if [ "$prefer_rsa" = "true" ]; then
            echo "PowerShell not available for RSA key generation"
            echo "DEBUG: PowerShell check failed - command -v pwsh returned: $(command -v pwsh || echo 'NOT FOUND')"
        fi
    fi
    
    # Fallback to AES encryption
    echo "Generating AES encryption key..."
    bc_ensure_encryption_key "$key_dir" "$key_name"
    return $?
}

# Function to generate BC-compatible encryption key instead of importing to database
bc_generate_bc_encryption_key() {
    local key_file="${1:-/home/bcserver/Keys/bc.key}"
    local key_password_file="${2:-/home/bcserver/Keys/bc-key-password.txt}"
    
    echo "Generating BC-compatible RSA encryption key..."
    
    local key_dir=$(dirname "$key_file")
    
    # Check if PowerShell is available
    if ! command -v pwsh &> /dev/null; then
        echo "ERROR: PowerShell (pwsh) is required for RSA key generation"
        return 1
    fi
    
    # Generate RSA key using PowerShell script
    if bc_generate_rsa_key "$key_dir" "$(basename "$key_file")"; then
        echo "✅ RSA key generated successfully"
        echo "📁 Key file: $key_file"
        
        if [ -f "$key_password_file" ]; then
            echo "🔑 Password file: $key_password_file"
            echo "⚠️  Keep the password file secure - it's needed for decryption!"
        fi
        
        echo ""
        echo "🎯 Next steps:"
        echo "1. The RSA key is ready for BC Server to use"
        echo "2. Use bc_encrypt_password_rsa to encrypt database passwords"
        echo "3. Set ProtectedDatabasePassword in CustomSettings.config"
        echo "4. BC Server will automatically use the key for decryption"
        
        return 0
    else
        echo "❌ Failed to generate RSA key"
        return 1
    fi
}

# Function to test complete RSA encryption workflow
bc_test_rsa_workflow() {
    local test_password="TestPassword123"
    local key_file="${1:-/home/bcserver/Keys/bc.key}"
    
    echo "🧪 Testing complete RSA encryption workflow..."
    echo ""
    
    # Check if key exists
    if [ ! -f "$key_file" ]; then
        echo "❌ Key file not found: $key_file"
        echo "💡 Run bc_generate_bc_encryption_key first"
        return 1
    fi
    
    # Detect key type
    local key_type=$(bc_detect_key_type "$key_file")
    echo "🔍 Key type: $key_type"
    
    if [ "$key_type" != "RSA" ]; then
        echo "❌ RSA key required for this test"
        return 1
    fi
    
    # Test password encryption
    echo "🔐 Testing password encryption..."
    local encrypted_password
    if encrypted_password=$(bc_encrypt_password_rsa "$test_password" "$key_file"); then
        echo "✅ Password encryption successful"
        echo "📝 Encrypted password: ${encrypted_password:0:50}..."
        echo "📏 Length: ${#encrypted_password} characters"
    else
        echo "❌ Password encryption failed"
        return 1
    fi
    
    # Test configuration update
    echo ""
    echo "📋 Testing configuration update..."
    local test_config=$(mktemp --suffix=.config)
    cat > "$test_config" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<appSettings>
  <add key="DatabaseServer" value="sql" />
  <add key="DatabaseUserName" value="sa" />
  <add key="ServerInstance" value="BC" />
</appSettings>
EOF
    
    if bc_update_config_rsa "$test_config" "$test_password" "$key_file"; then
        echo "✅ Configuration update successful"
        echo "📄 Updated config contains:"
        grep -A 1 -B 1 "ProtectedDatabasePassword" "$test_config" || echo "  No ProtectedDatabasePassword found"
    else
        echo "❌ Configuration update failed"
        rm -f "$test_config"
        return 1
    fi
    
    rm -f "$test_config"
    
    echo ""
    echo "🎉 RSA encryption workflow test completed successfully!"
    echo ""
    echo "📋 Summary:"
    echo "  ✅ RSA key is properly formatted"
    echo "  ✅ Password encryption works"
    echo "  ✅ Configuration update works"
    echo "  ✅ Ready for BC Server deployment"
    
    return 0
}

# Function to test RSA encryption setup
bc_test_rsa_encryption() {
    local key_file="${1:-/home/bcserver/Keys/bc.key}"
    
    echo "Testing RSA encryption setup..."
    
    # Check if key exists and is RSA
    if [ ! -f "$key_file" ]; then
        echo "❌ Key file not found: $key_file"
        return 1
    fi
    
    local key_type=$(bc_detect_key_type "$key_file")
    echo "🔍 Key type detected: $key_type"
    
    if [ "$key_type" = "RSA" ]; then
        echo "✅ RSA key found"
        
        # Check if PowerShell is available
        if command -v pwsh &> /dev/null; then
            echo "✅ PowerShell available"
        else
            echo "❌ PowerShell not available (required for RSA operations)"
            return 1
        fi
        
        # Test password encryption
        if encrypted_password=$(bc_encrypt_password_rsa "TestPassword123"); then
            echo "✅ Password encryption test successful"
            echo "   Encrypted: ${encrypted_password:0:50}..."
        else
            echo "❌ Password encryption test failed"
            return 1
        fi
        
    elif [ "$key_type" = "AES" ]; then
        echo "ℹ️  AES key found (fallback mode)"
        
        # Test AES encryption
        if encrypted_password=$(bc_encrypt_password "TestPassword123" "$key_file"); then
            echo "✅ AES password encryption test successful"
        else
            echo "❌ AES password encryption test failed"
            return 1
        fi
        
    else
        echo "❌ Unknown or invalid key type"
        return 1
    fi
    
    echo "✅ Encryption setup test completed successfully"
    return 0
}

# Function to force regenerate RSA key and replace database key (for caching issues)
bc_force_regenerate_rsa_key() {
    local key_dir="${1:-/home/bcserver/Keys}"
    local key_name="${2:-bc.key}"
    local key_path="$key_dir/$key_name"
    local password_file="$key_dir/bc-key-password.txt"
    
    echo "🔄 Force regenerating RSA key to resolve caching/database mismatch..."
    
    # Remove existing key files to force fresh generation
    if [ -f "$key_path" ]; then
        echo "Removing existing key file: $key_path"
        rm -f "$key_path"
    fi
    
    if [ -f "$password_file" ]; then
        echo "Removing existing password file: $password_file"
        rm -f "$password_file"
    fi
    
    if [ -f "$key_dir/Secret.key" ]; then
        echo "Removing existing Secret.key file"
        rm -f "$key_dir/Secret.key"
    fi
    
    # Force fresh generation
    echo "Generating new RSA key..."
    if bc_generate_rsa_key "$key_dir" "$key_name" "true"; then
        echo "✅ New RSA key generated successfully"
        
        # Sync the new key to the database (replace existing)
        echo "🔄 Syncing new RSA key to database..."
        if bc_sync_rsa_key_to_database "$key_path"; then
            echo "✅ RSA key synced to database successfully"
        else
            echo "⚠️  Failed to sync RSA key to database - key will be used from file only"
        fi
        
        return 0
    else
        echo "❌ Failed to regenerate RSA key"
        return 1
    fi
}

# Function to ensure RSA key is properly synced between file and database
bc_sync_rsa_key_to_database() {
    local key_file="${1:-/home/bcserver/Keys/bc.key}"
    local database_server="${2:-sql}"
    local database_name="${3:-CRONUS}"
    local database_user="${4:-sa}"
    local database_password="${5:-P@ssw0rd123!}"
    
    echo "🔄 Syncing RSA key between file and database..."
    
    if [ ! -f "$key_file" ]; then
        echo "❌ RSA key file not found: $key_file"
        return 1
    fi
    
    # Check if PowerShell and import script are available
    if ! command -v pwsh &> /dev/null; then
        echo "⚠️  PowerShell not available - skipping database key sync"
        return 0
    fi
    
    if [ ! -f "/home/import-rsa-key-to-database.ps1" ]; then
        echo "⚠️  RSA key import script not found - skipping database key sync"
        return 0
    fi
    
    # Get password file path
    local password_file=""
    local key_dir=$(dirname "$key_file")
    if [ -f "$key_dir/bc-key-password.txt" ]; then
        password_file="$key_dir/bc-key-password.txt"
    fi
    
    echo "Importing RSA key to database (replacing existing if present)..."
    
    # Build PowerShell command
    local ps_cmd="pwsh -File /home/import-rsa-key-to-database.ps1"
    ps_cmd="$ps_cmd -DatabaseServer \"$database_server\""
    ps_cmd="$ps_cmd -DatabaseName \"$database_name\""
    ps_cmd="$ps_cmd -DatabaseUser \"$database_user\""
    ps_cmd="$ps_cmd -DatabasePassword \"$database_password\""
    ps_cmd="$ps_cmd -KeyPath \"$key_file\""
    ps_cmd="$ps_cmd -Force"
    
    if [ -n "$password_file" ]; then
        ps_cmd="$ps_cmd -PasswordFile \"$password_file\""
    fi
    
    if eval "$ps_cmd"; then
        echo "✅ RSA key successfully synced to database"
        return 0
    else
        echo "❌ Failed to sync RSA key to database"
        return 1
    fi
}
