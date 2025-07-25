#!/bin/bash
# import-encryption-key-to-db.sh - Import BC encryption key into database
# This script imports the encryption key into the BC database for ProtectedDatabasePassword support

set -e

# Configuration
SERVER_INSTANCE="${BC_SERVER_INSTANCE:-BC}"
DATABASE_SERVER="${BC_DATABASE_SERVER:-sql}"
DATABASE_NAME="${BC_DATABASE_NAME:-CRONUS}"
KEY_FILE="${BC_KEY_FILE:-/home/bcserver/Keys/bc.key}"
PASSWORD_FILE="${BC_PASSWORD_FILE:-/home/bcserver/Keys/bc-key-password.txt}"
SA_PASSWORD="${SA_PASSWORD:-}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-instance)
            SERVER_INSTANCE="$2"
            shift 2
            ;;
        --database-server)
            DATABASE_SERVER="$2"
            shift 2
            ;;
        --database-name)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        --password-file)
            PASSWORD_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Import BC encryption key into database for ProtectedDatabasePassword support"
            echo ""
            echo "Options:"
            echo "  --server-instance NAME    BC Server instance name (default: BC)"
            echo "  --database-server HOST    Database server hostname (default: sql)"
            echo "  --database-name NAME      Database name (default: CRONUS)"
            echo "  --key-file PATH          Path to encryption key file"
            echo "  --password-file PATH     Path to key password file"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "BC Encryption Key Import Tool"
log_info "============================="

# Check if SA_PASSWORD is set
if [ -z "$SA_PASSWORD" ]; then
    log_error "SA_PASSWORD environment variable is required for database connection"
    exit 1
fi

# Check if key file exists
if [ ! -f "$KEY_FILE" ]; then
    log_error "Key file not found: $KEY_FILE"
    exit 1
fi

log_info "Key file: $KEY_FILE"

# Source encryption functions to detect key type
source /home/bc-rsa-encryption-functions.sh

# Detect key type
KEY_TYPE=$(bc_detect_key_type "$KEY_FILE")
log_info "Key type detected: $KEY_TYPE"

case "$KEY_TYPE" in
    "RSA")
        log_info "RSA key detected - proceeding with key import"
        ;;
    "AES")
        log_warning "AES key detected - key import not typically needed for AES"
        log_warning "BC Server can use AES keys directly without database import"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Import cancelled"
            exit 0
        fi
        ;;
    *)
        log_error "Unknown or invalid key type: $KEY_TYPE"
        exit 1
        ;;
esac

# Check if PowerShell is available
if ! command -v pwsh &> /dev/null; then
    log_error "PowerShell Core (pwsh) is required for key import"
    log_error "Please install PowerShell Core to use this feature"
    exit 1
fi

log_success "PowerShell Core found"

# Check if password file exists
if [ -f "$PASSWORD_FILE" ]; then
    log_info "Password file found: $PASSWORD_FILE"
    HAS_PASSWORD=true
else
    log_warning "Password file not found: $PASSWORD_FILE"
    log_warning "Will attempt import without password"
    HAS_PASSWORD=false
fi

# Find the PowerShell script for database import
IMPORT_PS_SCRIPT=""
SCRIPT_NAME="import-rsa-key-to-database.ps1"

# Look for the script in common locations
for location in "/home/$SCRIPT_NAME" "$(dirname "$0")/$SCRIPT_NAME" "./$SCRIPT_NAME"; do
    if [ -f "$location" ]; then
        IMPORT_PS_SCRIPT="$location"
        break
    fi
done

if [ -z "$IMPORT_PS_SCRIPT" ]; then
    log_error "PowerShell import script not found: $SCRIPT_NAME"
    log_error "Please ensure $SCRIPT_NAME is in the same directory or /home/"
    exit 1
fi

log_info "Using PowerShell script: $IMPORT_PS_SCRIPT"

# Execute the PowerShell script
log_info "Starting encryption key database import process..."

# Build PowerShell command arguments
PS_ARGS="-DatabaseServer \"$DATABASE_SERVER\" -DatabaseName \"$DATABASE_NAME\" -DatabaseUser \"sa\" -DatabasePassword \"$SA_PASSWORD\" -KeyPath \"$KEY_FILE\""

if [ "$HAS_PASSWORD" = "true" ]; then
    PS_ARGS="$PS_ARGS -PasswordFile \"$PASSWORD_FILE\""
fi

if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
    PS_ARGS="$PS_ARGS -Verbose"
fi

# Execute the PowerShell script with proper argument passing
if pwsh -File "$IMPORT_PS_SCRIPT" \
    -DatabaseServer "$DATABASE_SERVER" \
    -DatabaseName "$DATABASE_NAME" \
    -DatabaseUser "sa" \
    -DatabasePassword "$SA_PASSWORD" \
    -KeyPath "$KEY_FILE" \
    -PasswordFile "$PASSWORD_FILE"; then
    
    log_success "Encryption key import process completed"
    
    # Update configuration to enable ProtectedDatabasePassword
    if [ "$KEY_TYPE" = "RSA" ]; then
        log_info "Updating configuration for ProtectedDatabasePassword support..."
        
        # This would update the CustomSettings.config to use ProtectedDatabasePassword
        # instead of plain DatabasePassword when RSA key is imported
        CONFIG_FILE="/home/bcserver/CustomSettings.config"
        if [ -f "$CONFIG_FILE" ]; then
            log_info "Configuration file found: $CONFIG_FILE"
            log_info "Remember to encrypt your database password and update the config:"
            log_info "  <add key=\"ProtectedDatabasePassword\" value=\"[encrypted_password]\" />"
        fi
    fi
    
else
    log_error "Encryption key import failed"
    exit 1
fi

log_success "Import operation completed successfully!"
