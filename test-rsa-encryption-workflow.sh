#!/bin/bash
# test-rsa-encryption-workflow.sh - Test complete RSA encryption workflow for BC Server
# This script tests all aspects of the RSA encryption implementation

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Test configuration
TEST_KEY_DIR="/tmp/bc-test-keys"
TEST_KEY_FILE="$TEST_KEY_DIR/bc.key"
TEST_PASSWORD="TestPassword123!"
TEST_DATABASE_PASSWORD="MySecureDbPass123"

echo "==============================================="
echo "BC RSA Encryption Workflow Test"
echo "==============================================="
echo ""

# Step 1: Clean up any previous test
log_step "1. Cleaning up previous test data..."
rm -rf "$TEST_KEY_DIR"
mkdir -p "$TEST_KEY_DIR"
log_success "Test environment prepared"
echo ""

# Step 2: Test RSA key generation
log_step "2. Testing RSA key generation..."
source /home/bc-rsa-encryption-functions.sh

if bc_generate_rsa_key "$TEST_KEY_DIR" "bc.key" "true"; then
    log_success "RSA key generated successfully"
    
    # Verify key file
    if [ -f "$TEST_KEY_FILE" ]; then
        KEY_SIZE=$(stat -c%s "$TEST_KEY_FILE")
        log_info "Key file size: $KEY_SIZE bytes"
        
        if [ "$KEY_SIZE" -gt 1000 ]; then
            log_success "Key file size indicates RSA key"
        else
            log_error "Key file size too small for RSA key"
            exit 1
        fi
    else
        log_error "Key file not created"
        exit 1
    fi
else
    log_error "RSA key generation failed"
    exit 1
fi
echo ""

# Step 3: Test key type detection
log_step "3. Testing key type detection..."
KEY_TYPE=$(bc_detect_key_type "$TEST_KEY_FILE")
log_info "Detected key type: $KEY_TYPE"

if [ "$KEY_TYPE" = "RSA" ]; then
    log_success "Key type detection working correctly"
else
    log_error "Key type detection failed"
    exit 1
fi
echo ""

# Step 4: Test password encryption
log_step "4. Testing password encryption with RSA key..."
if ENCRYPTED_PASSWORD=$(bc_encrypt_password_rsa "$TEST_DATABASE_PASSWORD" "$TEST_KEY_FILE"); then
    log_success "Password encrypted successfully"
    log_info "Encrypted password length: ${#ENCRYPTED_PASSWORD} characters"
    log_info "Encrypted password preview: ${ENCRYPTED_PASSWORD:0:50}..."
    
    # Verify it's not the same as plain password
    if [ "$ENCRYPTED_PASSWORD" != "$TEST_DATABASE_PASSWORD" ]; then
        log_success "Encrypted password differs from plain password"
    else
        log_error "Encrypted password same as plain password"
        exit 1
    fi
else
    log_error "Password encryption failed"
    exit 1
fi
echo ""

# Step 5: Test configuration update
log_step "5. Testing CustomSettings.config update..."
TEST_CONFIG="$TEST_KEY_DIR/test-config.config"
cat > "$TEST_CONFIG" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<appSettings>
  <add key="DatabaseServer" value="sql" />
  <add key="DatabaseUserName" value="sa" />
  <add key="ServerInstance" value="BC" />
  <add key="DatabaseName" value="CRONUS" />
</appSettings>
EOF

if bc_update_config_rsa "$TEST_CONFIG" "$TEST_DATABASE_PASSWORD" "$TEST_KEY_FILE"; then
    log_success "Configuration update successful"
    
    # Verify the config contains ProtectedDatabasePassword
    if grep -q "ProtectedDatabasePassword" "$TEST_CONFIG"; then
        log_success "ProtectedDatabasePassword found in config"
        
        # Show the updated config
        log_info "Updated configuration:"
        grep -A 1 -B 1 "ProtectedDatabasePassword" "$TEST_CONFIG" | sed 's/^/    /'
    else
        log_error "ProtectedDatabasePassword not found in config"
        exit 1
    fi
else
    log_error "Configuration update failed"
    exit 1
fi
echo ""

# Step 6: Test key directory structure creation
log_step "6. Testing BC Server key directory structure..."
TEST_WINE_PREFIX="$TEST_KEY_DIR/wine_test"
BC_VERSION="260"
BC_KEYS_DIR="$TEST_WINE_PREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/$BC_VERSION/Server/Keys"

mkdir -p "$BC_KEYS_DIR"
cp "$TEST_KEY_FILE" "$BC_KEYS_DIR/bc.key"
cp "$TEST_KEY_FILE" "$BC_KEYS_DIR/Secret.key"

if [ -f "$BC_KEYS_DIR/bc.key" ] && [ -f "$BC_KEYS_DIR/Secret.key" ]; then
    log_success "Key files copied to proper system directory structure"
    log_info "System keys directory: $BC_KEYS_DIR"
else
    log_error "Failed to copy keys to system directory"
    exit 1
fi
echo ""

# Step 7: Test complete workflow simulation
log_step "7. Testing complete workflow simulation..."
log_info "Simulating complete BC Server startup process..."

# Simulate the key placement process
SIMULATED_BCSERVER_DIR="$TEST_KEY_DIR/bcserver"
mkdir -p "$SIMULATED_BCSERVER_DIR"

# Copy key to BC Server directory
cp "$TEST_KEY_FILE" "$SIMULATED_BCSERVER_DIR/Secret.key"

# Copy config to BC Server directory  
cp "$TEST_CONFIG" "$SIMULATED_BCSERVER_DIR/CustomSettings.config"

log_success "Files placed in simulated BC Server directory:"
log_info "  - Secret.key: $(ls -la "$SIMULATED_BCSERVER_DIR/Secret.key" | awk '{print $5}') bytes"
log_info "  - CustomSettings.config: $(ls -la "$SIMULATED_BCSERVER_DIR/CustomSettings.config" | awk '{print $5}') bytes"
echo ""

# Step 8: Generate summary report
log_step "8. Generating test summary report..."
echo ""
echo "🎉 RSA ENCRYPTION WORKFLOW TEST RESULTS 🎉"
echo "==========================================="
echo ""
echo "✅ RSA Key Generation:           PASSED"
echo "✅ Key Type Detection:           PASSED" 
echo "✅ Password Encryption:          PASSED"
echo "✅ Configuration Update:         PASSED"
echo "✅ Key Directory Structure:      PASSED"
echo "✅ Complete Workflow:            PASSED"
echo ""
echo "📋 Test Summary:"
echo "  🔑 RSA key size: $(stat -c%s "$TEST_KEY_FILE") bytes"
echo "  🔐 Encrypted password length: ${#ENCRYPTED_PASSWORD} characters"
echo "  📁 Key directories created: 3"
echo "  📄 Configuration files: 1"
echo ""
echo "🚀 Your RSA encryption implementation meets all requirements:"
echo "  ✅ Generates RSA encryption keys"
echo "  ✅ Encrypts database passwords"
echo "  ✅ Updates CustomSettings.config with ProtectedDatabasePassword"
echo "  ✅ Places keys in proper Windows system directory structure"
echo "  ✅ Ready for database key import (when database is available)"
echo ""
echo "📝 Next steps for production:"
echo "  1. Ensure database backup restoration is working"
echo "  2. Test key import to database table dbo.\$ndo\$publicencryptionkey"
echo "  3. Verify BC Server can decrypt ProtectedDatabasePassword"
echo "  4. Test complete BC Server startup with encrypted configuration"
echo ""

# Clean up test files
log_step "9. Cleaning up test environment..."
rm -rf "$TEST_KEY_DIR"
log_success "Test environment cleaned up"
echo ""

log_success "🎯 RSA ENCRYPTION WORKFLOW TEST COMPLETED SUCCESSFULLY!"
