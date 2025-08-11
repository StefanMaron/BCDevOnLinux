#!/bin/bash
# test-bc-password-encryption.sh - Comprehensive test suite for BC password encryption

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((TESTS_RUN++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

# Setup test environment
TEST_DIR="/tmp/bc-encryption-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Business Central Password Encryption Test Suite"
echo "=============================================="
echo ""

# Test 1: Basic encryption functionality
log_test "Testing basic encryption functionality"
cat > test-basic.sh << 'EOF'
#!/bin/bash
source /home/scripts/bc/bc-encryption-functions.sh

# Create test key
mkdir -p keys
openssl rand -out keys/test.key 32

# Test encryption
PASSWORD="TestPassword123!"
ENCRYPTED=$(bc_encrypt_password "$PASSWORD" "keys/test.key")

if [ -n "$ENCRYPTED" ] && [ ${#ENCRYPTED} -gt 20 ]; then
    echo "SUCCESS: $ENCRYPTED"
    exit 0
else
    echo "FAILED"
    exit 1
fi
EOF
chmod +x test-basic.sh

if ./test-basic.sh > result.txt 2>&1; then
    ENCRYPTED=$(grep "SUCCESS:" result.txt | cut -d' ' -f2)
    log_pass "Basic encryption works - Generated: ${ENCRYPTED:0:20}..."
else
    log_fail "Basic encryption failed"
    cat result.txt
fi

# Test 2: Encryption produces different results each time (due to random IV)
log_test "Testing encryption randomness (different outputs for same input)"
cat > test-random.sh << 'EOF'
#!/bin/bash
source /home/scripts/bc/bc-encryption-functions.sh

# Use the same key from test 1
PASSWORD="TestPassword123!"
ENC1=$(bc_encrypt_password "$PASSWORD" "keys/test.key")
ENC2=$(bc_encrypt_password "$PASSWORD" "keys/test.key")

if [ "$ENC1" != "$ENC2" ]; then
    echo "SUCCESS: Outputs are different"
    echo "ENC1: $ENC1"
    echo "ENC2: $ENC2"
    exit 0
else
    echo "FAILED: Outputs are identical"
    exit 1
fi
EOF
chmod +x test-random.sh

if ./test-random.sh > result2.txt 2>&1; then
    log_pass "Encryption produces different outputs (random IV working)"
else
    log_fail "Encryption not using random IV"
    cat result2.txt
fi

# Test 3: PowerShell compatibility test
log_test "Testing PowerShell decryption compatibility"
cat > test-decrypt.ps1 << 'EOF'
#!/usr/bin/env pwsh
param(
    [string]$KeyPath,
    [string]$EncryptedPassword,
    [string]$ExpectedPassword
)

try {
    $keyBytes = [System.IO.File]::ReadAllBytes($KeyPath)
    $encryptedBytes = [Convert]::FromBase64String($EncryptedPassword)
    
    # Extract IV and encrypted data
    $iv = $encryptedBytes[0..15]
    $encryptedData = $encryptedBytes[16..($encryptedBytes.Length - 1)]
    
    # Create AES decryptor
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $keyBytes
    $aes.IV = $iv
    
    # Decrypt
    $decryptor = $aes.CreateDecryptor()
    $decrypted = $decryptor.TransformFinalBlock($encryptedData, 0, $encryptedData.Length)
    $password = [System.Text.Encoding]::UTF8.GetString($decrypted)
    
    if ($password -eq $ExpectedPassword) {
        Write-Host "SUCCESS: Decrypted correctly"
        exit 0
    } else {
        Write-Host "FAILED: Expected '$ExpectedPassword' but got '$password'"
        exit 1
    }
} catch {
    Write-Host "ERROR: $_"
    exit 1
}
EOF

if [ -n "$ENCRYPTED" ] && command -v pwsh >/dev/null 2>&1; then
    if pwsh test-decrypt.ps1 -KeyPath "keys/test.key" -EncryptedPassword "$ENCRYPTED" -ExpectedPassword "TestPassword123!" > result3.txt 2>&1; then
        log_pass "PowerShell can decrypt bash-encrypted passwords"
    else
        log_fail "PowerShell decryption failed"
        cat result3.txt
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} PowerShell not available or no encrypted password"
fi

# Test 4: Config file update test
log_test "Testing config file password update"
cat > test-config.xml << 'EOF'
<configuration>
  <appSettings>
    <add key="DatabaseServer" value="localhost" />
    <add key="DatabaseUserName" value="sa" />
    <add key="DatabasePassword" value="${SA_PASSWORD}" />
    <add key="EnableSqlConnectionEncryption" value="true" />
  </appSettings>
</configuration>
EOF

cat > test-config.sh << 'EOF'
#!/bin/bash
source /home/scripts/bc/bc-encryption-functions.sh

if bc_update_config_password "test-config.xml" "MySecretPass123!" "keys/test.key"; then
    # Check if ProtectedDatabasePassword was added
    if grep -q "ProtectedDatabasePassword" test-config.xml; then
        # Check if plain password was removed
        if ! grep -q "DatabasePassword" test-config.xml; then
            echo "SUCCESS"
            exit 0
        else
            echo "FAILED: Plain password still exists"
            exit 1
        fi
    else
        echo "FAILED: ProtectedDatabasePassword not added"
        exit 1
    fi
else
    echo "FAILED: Update function failed"
    exit 1
fi
EOF
chmod +x test-config.sh

if ./test-config.sh > result4.txt 2>&1; then
    log_pass "Config file password update works"
    echo "Updated config:"
    grep -E "(DatabaseUserName|ProtectedDatabasePassword)" test-config.xml | sed 's/^/  /'
else
    log_fail "Config file update failed"
    cat result4.txt
fi

# Test 5: Integration test with actual BC config format
log_test "Testing with actual BC CustomSettings.config format"
cat > bc-config.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings file="CustomSettings.config">
    <add key="NetworkProtocol" value="Default" />
    <add key="DatabaseServer" value="sql" />
    <add key="DatabaseInstance" value="" />
    <add key="DatabaseName" value="BC" />
    <add key="DatabaseUserName" value="sa" />
    <add key="DatabasePassword" value="PlainTextPassword123" />
    <add key="EnableSqlConnectionEncryption" value="true" />
    <add key="ServerInstance" value="BC" />
    <add key="ClientServicesCredentialType" value="NavUserPassword" />
  </appSettings>
</configuration>
EOF

cp bc-config.xml bc-config-backup.xml
if bc_update_config_password "bc-config.xml" "ActualPassword456!" "keys/test.key" >/dev/null 2>&1; then
    if grep -q "ProtectedDatabasePassword" bc-config.xml && ! grep -q "DatabasePassword" bc-config.xml; then
        log_pass "BC config format handled correctly"
        PROTECTED_PASS=$(grep "ProtectedDatabasePassword" bc-config.xml | sed 's/.*value="\([^"]*\)".*/\1/')
        echo "  Generated ProtectedDatabasePassword: ${PROTECTED_PASS:0:30}..."
    else
        log_fail "BC config format not handled properly"
    fi
else
    log_fail "Failed to update BC config"
fi

# Test 6: Error handling - missing key file
log_test "Testing error handling for missing key file"
if ERROR_MSG=$(bc_encrypt_password "test" "/nonexistent/key.file" 2>&1); then
    log_fail "Should have failed with missing key"
else
    if echo "$ERROR_MSG" | grep -q "not found"; then
        log_pass "Proper error handling for missing key"
    else
        log_fail "Unexpected error message: $ERROR_MSG"
    fi
fi

# Test 7: Key generation function
log_test "Testing key generation function"
rm -rf keys2
if bc_ensure_encryption_key "keys2" "newtest.key" >/dev/null 2>&1; then
    if [ -f "keys2/newtest.key" ] && [ -f "keys2/BC210.key" ] && [ -f "keys2/Secret.key" ]; then
        KEY_SIZE=$(stat -c%s "keys2/newtest.key" 2>/dev/null || stat -f%z "keys2/newtest.key" 2>/dev/null)
        if [ "$KEY_SIZE" -eq 32 ]; then
            log_pass "Key generation creates all required files with correct size"
        else
            log_fail "Generated key has wrong size: $KEY_SIZE (expected 32)"
        fi
    else
        log_fail "Not all required key files were created"
    fi
else
    log_fail "Key generation function failed"
fi

# Test 8: Full integration test
log_test "Full integration test with setup script"
if [ -f "/home/scripts/bc/setup-bc-encryption.sh" ]; then
    if /home/scripts/bc/setup-bc-encryption.sh --keys-dir "$TEST_DIR/full-test" --no-verify-sql >/dev/null 2>&1; then
        if [ -f "$TEST_DIR/full-test/example-database-config.xml" ]; then
            if grep -q "ProtectedDatabasePassword" "$TEST_DIR/full-test/example-database-config.xml"; then
                log_pass "Full setup script integration works"
            else
                log_fail "Setup script didn't generate encrypted password"
            fi
        else
            log_fail "Setup script didn't generate example config"
        fi
    else
        log_fail "Setup script failed"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} Setup script not found"
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

# Summary
echo ""
echo "Test Summary"
echo "============"
echo -e "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi