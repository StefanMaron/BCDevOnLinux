#!/bin/bash
# Test script for BC encryption setup

set -e

echo "Testing BC Encryption Setup"
echo "=========================="

# Test directory for our test
TEST_DIR="/tmp/bc-encryption-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

echo ""
echo "1. Testing encryption key generation..."
./scripts/bc/setup-bc-encryption.sh --keys-dir "$TEST_DIR/keys" --no-verify-sql

echo ""
echo "2. Verifying generated files..."
if [ -f "$TEST_DIR/keys/bc.key" ]; then
    echo "✓ Primary key created"
    SIZE=$(stat -c%s "$TEST_DIR/keys/bc.key" 2>/dev/null || stat -f%z "$TEST_DIR/keys/bc.key" 2>/dev/null)
    echo "  Key size: $SIZE bytes"
else
    echo "✗ Primary key NOT created"
    exit 1
fi

echo ""
echo "3. Checking compatibility keys..."
for key in BC210.key BC220.key BC230.key BC240.key Secret.key; do
    if [ -f "$TEST_DIR/keys/$key" ]; then
        echo "✓ $key created"
    else
        echo "✗ $key NOT created"
    fi
done

echo ""
echo "4. Verifying permissions..."
PERMS=$(stat -c%a "$TEST_DIR/keys/bc.key" 2>/dev/null || stat -f%p "$TEST_DIR/keys/bc.key" 2>/dev/null | tail -c 4)
if [ "$PERMS" = "600" ]; then
    echo "✓ Key permissions are correct (600)"
else
    echo "✗ Key permissions are incorrect: $PERMS (expected 600)"
fi

echo ""
echo "5. Testing backup functionality..."
# First create a key
./scripts/bc/setup-bc-encryption.sh --keys-dir "$TEST_DIR/keys" --key-name "test.key" --no-verify-sql >/dev/null 2>&1
# Now run again to trigger backup
./scripts/bc/setup-bc-encryption.sh --keys-dir "$TEST_DIR/keys" --key-name "test.key" --no-verify-sql >/dev/null 2>&1
if ls "$TEST_DIR/keys/test.key.backup."* >/dev/null 2>&1; then
    echo "✓ Backup created successfully"
    BACKUP_COUNT=$(ls "$TEST_DIR/keys/test.key.backup."* 2>/dev/null | wc -l)
    echo "  Found $BACKUP_COUNT backup(s)"
else
    echo "✗ No backup created"
fi

echo ""
echo "6. Checking verification script..."
if [ -f "$TEST_DIR/keys/verify-encryption.ps1" ]; then
    echo "✓ Verification script created"
    if [ -x "$TEST_DIR/keys/verify-encryption.ps1" ]; then
        echo "✓ Verification script is executable"
    else
        echo "✗ Verification script is not executable"
    fi
else
    echo "✗ Verification script NOT created"
fi

echo ""
echo "7. Testing key content randomness..."
# Check if key contains non-printable characters (indicating binary data)
if file "$TEST_DIR/keys/bc.key" | grep -q "data"; then
    echo "✓ Key appears to be binary data"
else
    echo "✗ Key doesn't appear to be binary data"
fi

# Calculate entropy
HEX_DUMP=$(xxd -p "$TEST_DIR/keys/bc.key" | tr -d '\n')
UNIQUE_BYTES=$(echo "$HEX_DUMP" | fold -w2 | sort -u | wc -l)
TOTAL_BYTES=32
ENTROPY=$(( UNIQUE_BYTES * 100 / TOTAL_BYTES ))
echo "  Key entropy: $ENTROPY% unique bytes (should be >90% for good randomness)"

echo ""
echo "8. Cleanup..."
rm -rf "$TEST_DIR"
echo "✓ Test directory cleaned up"

echo ""
echo "=========================="
echo "All tests completed!"
echo ""
echo "To test in a real environment with SQL verification:"
echo "  ./scripts/bc/setup-bc-encryption.sh"
echo ""
echo "To verify an existing setup:"
echo "  pwsh /home/bcserver/Keys/verify-encryption.ps1"