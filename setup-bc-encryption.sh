#!/bin/bash
# setup-bc-encryption.sh - Comprehensive BC encryption setup for SQL Server communication
# This script handles all aspects of encryption key generation and configuration
# that are typically done by BC PowerShell cmdlets

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
KEYS_DIR="${BC_KEYS_DIR:-/home/bcserver/Keys}"
KEY_NAME="${BC_KEY_NAME:-bc.key}"
KEY_PATH="$KEYS_DIR/$KEY_NAME"
KEY_SIZE_BYTES=32  # 256-bit key for AES-256
BACKUP_PREVIOUS=true
VERIFY_SQL_CERT=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keys-dir)
            KEYS_DIR="$2"
            KEY_PATH="$KEYS_DIR/$KEY_NAME"
            shift 2
            ;;
        --key-name)
            KEY_NAME="$2"
            KEY_PATH="$KEYS_DIR/$KEY_NAME"
            shift 2
            ;;
        --no-backup)
            BACKUP_PREVIOUS=false
            shift
            ;;
        --no-verify-sql)
            VERIFY_SQL_CERT=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keys-dir DIR        Directory to store keys (default: /home/bcserver/Keys)"
            echo "  --key-name NAME       Key filename (default: bc.key)"
            echo "  --no-backup          Don't backup existing keys"
            echo "  --no-verify-sql      Skip SQL Server certificate verification"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check if OpenSSL is available
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Function to create keys directory with proper permissions
create_keys_directory() {
    log_info "Setting up keys directory: $KEYS_DIR"
    
    if [ ! -d "$KEYS_DIR" ]; then
        mkdir -p "$KEYS_DIR"
        log_success "Created keys directory"
    else
        log_info "Keys directory already exists"
    fi
    
    # Set restrictive permissions (only owner can read/write)
    chmod 700 "$KEYS_DIR"
    log_info "Set directory permissions to 700"
}

# Function to backup existing key if present
backup_existing_key() {
    if [ -f "$KEY_PATH" ] && [ "$BACKUP_PREVIOUS" = true ]; then
        local backup_name="${KEY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing key to: $backup_name"
        cp "$KEY_PATH" "$backup_name"
        chmod 600 "$backup_name"
        log_success "Existing key backed up"
    fi
}

# Function to generate encryption key
generate_encryption_key() {
    log_info "Generating new $((KEY_SIZE_BYTES * 8))-bit encryption key..."
    
    # Use OpenSSL to generate cryptographically secure random bytes
    if openssl rand -out "$KEY_PATH" $KEY_SIZE_BYTES; then
        log_success "Encryption key generated successfully"
    else
        log_error "Failed to generate encryption key"
        exit 1
    fi
    
    # Set restrictive permissions on the key file
    chmod 600 "$KEY_PATH"
    log_info "Set key file permissions to 600 (owner read/write only)"
}

# Function to verify key integrity
verify_key_integrity() {
    log_info "Verifying key integrity..."
    
    # Check file exists and is readable
    if [ ! -r "$KEY_PATH" ]; then
        log_error "Key file is not readable: $KEY_PATH"
        return 1
    fi
    
    # Check file size
    local actual_size=$(stat -c%s "$KEY_PATH" 2>/dev/null || stat -f%z "$KEY_PATH" 2>/dev/null)
    if [ "$actual_size" -ne "$KEY_SIZE_BYTES" ]; then
        log_error "Key file size mismatch. Expected: $KEY_SIZE_BYTES bytes, Actual: $actual_size bytes"
        return 1
    fi
    
    # Generate checksum for verification
    local checksum=$(openssl dgst -sha256 "$KEY_PATH" | awk '{print $2}')
    log_info "Key SHA256 checksum: $checksum"
    
    log_success "Key integrity verified"
    return 0
}

# Function to create compatibility copies for different BC versions
create_compatibility_copies() {
    log_info "Creating compatibility copies for different BC versions..."
    
    local bc_versions=("BC210" "BC220" "BC230" "BC240")
    
    for version in "${bc_versions[@]}"; do
        local version_key="$KEYS_DIR/${version}.key"
        if [ ! -f "$version_key" ]; then
            cp "$KEY_PATH" "$version_key"
            chmod 600 "$version_key"
            log_info "Created ${version}.key"
        fi
    done
    
    # Also create a Secret.key copy (used by some BC configurations)
    local secret_key="$KEYS_DIR/Secret.key"
    if [ ! -f "$secret_key" ]; then
        cp "$KEY_PATH" "$secret_key"
        chmod 600 "$secret_key"
        log_info "Created Secret.key"
    fi
    
    log_success "Compatibility copies created"
}

# Function to verify SQL Server certificate (if TLS is enabled)
verify_sql_certificate() {
    if [ "$VERIFY_SQL_CERT" != true ]; then
        log_info "Skipping SQL certificate verification (disabled)"
        return 0
    fi
    
    log_info "Checking SQL Server TLS/SSL configuration..."
    
    local sql_server="${BC_DATABASE_SERVER:-sql}"
    local sql_port="${BC_DATABASE_PORT:-1433}"
    
    # Try to connect to SQL Server and check certificate
    if timeout 5 openssl s_client -connect "$sql_server:$sql_port" -servername "$sql_server" </dev/null 2>/dev/null | grep -q "Certificate chain"; then
        log_success "SQL Server TLS certificate detected"
        
        # Extract certificate details
        local cert_info=$(timeout 5 openssl s_client -connect "$sql_server:$sql_port" -servername "$sql_server" </dev/null 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null)
        if [ -n "$cert_info" ]; then
            log_info "Certificate details:"
            echo "$cert_info" | sed 's/^/  /'
        fi
    else
        log_warning "No TLS certificate detected on SQL Server (connection may use encryption without certificate validation)"
    fi
}

# Function to display key locations for BC configuration
display_key_locations() {
    log_info "Key locations for BC configuration:"
    echo ""
    echo "  Primary key location: $KEY_PATH"
    echo "  Keys directory: $KEYS_DIR"
    echo ""
    echo "Business Central will look for the key in these locations:"
    echo "  - Windows path: C:\\ProgramData\\Microsoft\\Microsoft Dynamics NAV\\[version]\\Server\\Keys\\$KEY_NAME"
    echo "  - Wine path: $WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/[version]/Server/Keys/$KEY_NAME"
    echo "  - Service directory: [BC_Service_Directory]/Secret.key"
    echo ""
}

# Function to generate PowerShell verification script
generate_verification_script() {
    local verify_script="$KEYS_DIR/verify-encryption.ps1"
    
    cat > "$verify_script" << 'EOF'
#!/usr/bin/env pwsh
# Verify BC encryption key setup

param(
    [string]$KeyPath = "/home/bcserver/Keys/bc.key"
)

Write-Host "BC Encryption Key Verification Script" -ForegroundColor Blue
Write-Host "=====================================" -ForegroundColor Blue

# Check if key file exists
if (Test-Path $KeyPath) {
    Write-Host "[OK] Key file exists: $KeyPath" -ForegroundColor Green
    
    # Read key and check size
    $keyBytes = [System.IO.File]::ReadAllBytes($KeyPath)
    Write-Host "[INFO] Key size: $($keyBytes.Length) bytes ($($keyBytes.Length * 8) bits)" -ForegroundColor Cyan
    
    # Generate key hash for verification
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($keyBytes)
    $hashString = [BitConverter]::ToString($hash).Replace("-", "").ToLower()
    Write-Host "[INFO] Key SHA256: $hashString" -ForegroundColor Cyan
    
    # Check if key appears to be random (basic entropy check)
    $uniqueBytes = ($keyBytes | Select-Object -Unique).Count
    $entropy = [Math]::Round($uniqueBytes / $keyBytes.Length * 100, 2)
    Write-Host "[INFO] Key entropy: $entropy% unique bytes" -ForegroundColor Cyan
    
    if ($entropy -gt 90) {
        Write-Host "[OK] Key appears to have good randomness" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Key may have low entropy" -ForegroundColor Yellow
    }
} else {
    Write-Host "[ERROR] Key file not found: $KeyPath" -ForegroundColor Red
    exit 1
}

# Test BC configuration access
Write-Host "`nChecking BC configuration..." -ForegroundColor Blue
$configPath = "/home/bcserver/CustomSettings.config"
if (Test-Path $configPath) {
    Write-Host "[OK] BC configuration found" -ForegroundColor Green
    
    # Check encryption settings
    [xml]$config = Get-Content $configPath
    $encryptionProvider = $config.configuration.appSettings.add | Where-Object { $_.key -eq "EncryptionProvider" } | Select-Object -ExpandProperty value
    $sqlEncryption = $config.configuration.appSettings.add | Where-Object { $_.key -eq "EnableSqlConnectionEncryption" } | Select-Object -ExpandProperty value
    
    Write-Host "[INFO] Encryption Provider: $encryptionProvider" -ForegroundColor Cyan
    Write-Host "[INFO] SQL Encryption Enabled: $sqlEncryption" -ForegroundColor Cyan
} else {
    Write-Host "[WARNING] BC configuration not found" -ForegroundColor Yellow
}

Write-Host "`nVerification complete!" -ForegroundColor Green
EOF
    
    chmod +x "$verify_script"
    log_info "Created verification script: $verify_script"
}

# Main execution
main() {
    log_info "Business Central Encryption Setup"
    log_info "================================="
    
    # Check dependencies
    check_dependencies
    
    # Create keys directory
    create_keys_directory
    
    # Backup existing key if present
    backup_existing_key
    
    # Generate new encryption key
    generate_encryption_key
    
    # Verify key integrity
    if ! verify_key_integrity; then
        log_error "Key verification failed"
        exit 1
    fi
    
    # Create compatibility copies
    create_compatibility_copies
    
    # Verify SQL certificate configuration
    verify_sql_certificate
    
    # Generate verification script
    generate_verification_script
    
    # Display key locations
    display_key_locations
    
    log_success "BC encryption setup completed successfully!"
    log_info "You can verify the setup by running: pwsh $KEYS_DIR/verify-encryption.ps1"
}

# Function to encrypt database password
encrypt_database_password() {
    local password="$1"
    local key_file="${2:-$KEY_PATH}"
    
    if [ ! -f "$key_file" ]; then
        log_error "Key file not found for password encryption: $key_file"
        return 1
    fi
    
    # Read key as hex
    local key_hex=$(xxd -p -c 32 "$key_file")
    
    # Generate random IV
    local iv_hex=$(openssl rand -hex 16)
    
    # Encrypt password using AES-256-CBC
    local encrypted_hex=$(echo -n "$password" | \
        openssl enc -aes-256-cbc -e -K "$key_hex" -iv "$iv_hex" | \
        xxd -p -c 256)
    
    # Create temporary file for binary concatenation
    local temp_file=$(mktemp)
    echo -n "$iv_hex" | xxd -r -p > "$temp_file"
    echo -n "$encrypted_hex" | xxd -r -p >> "$temp_file"
    
    # Base64 encode the result
    local protected_password=$(base64 -w 0 < "$temp_file")
    rm -f "$temp_file"
    
    echo "$protected_password"
}

# Function to generate example configuration with encrypted password
generate_example_config() {
    log_info "Generating example configuration with encrypted password..."
    
    local example_password="${SA_PASSWORD:-YourPassword123}"
    local encrypted_password=$(encrypt_database_password "$example_password")
    
    if [ -n "$encrypted_password" ]; then
        cat > "$KEYS_DIR/example-database-config.xml" << EOF
<!-- Example Business Central database configuration with encrypted password -->
<!-- Generated by setup-bc-encryption.sh -->
<configuration>
  <appSettings>
    <!-- Database connection settings -->
    <add key="DatabaseServer" value="${BC_DATABASE_SERVER:-sql}" />
    <add key="DatabaseInstance" value="" />
    <add key="DatabaseName" value="${BC_DATABASE_NAME:-BC}" />
    <add key="DatabaseUserName" value="sa" />
    
    <!-- Encrypted password (using bc.key) -->
    <!-- Original password: $example_password -->
    <add key="ProtectedDatabasePassword" value="$encrypted_password" />
    
    <!-- Enable SQL connection encryption -->
    <add key="EnableSqlConnectionEncryption" value="true" />
    <add key="TrustSQLServerCertificate" value="true" />
    
    <!-- Encryption provider configuration -->
    <add key="EncryptionProvider" value="LocalKeyFile" />
  </appSettings>
</configuration>
EOF
        log_success "Example configuration saved to: $KEYS_DIR/example-database-config.xml"
    else
        log_error "Failed to generate encrypted password for example"
    fi
}

# Run main function
main "$@"

# Generate example configuration if main succeeded
if [ $? -eq 0 ]; then
    generate_example_config
fi