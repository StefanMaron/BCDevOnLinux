# Business Central Encryption Setup

This document explains how the SQL encryption key setup works for Business Central Server on Linux/Wine.

## Overview

Business Central uses encryption keys to secure communication between the BC Service Tier and SQL Server. Traditionally, this is handled by PowerShell cmdlets like `New-NAVEncryptionKey`. Our implementation provides a pure bash alternative that achieves the same functionality.

## What the Encryption Key Does

1. **SQL Connection Encryption**: When `EnableSqlConnectionEncryption` is set to `true` in CustomSettings.config, BC encrypts all communication with SQL Server
2. **Data Protection**: The key is used to encrypt sensitive data stored in the database
3. **Service Authentication**: Helps authenticate the BC service tier to SQL Server

## Implementation Details

### Bash Implementation (`setup-bc-encryption.sh`)

Our bash script provides all the functionality of the BC PowerShell cmdlets:

```bash
# Basic usage
./setup-bc-encryption.sh

# Advanced options
./setup-bc-encryption.sh --keys-dir /custom/path --key-name custom.key
```

Features:
- Generates cryptographically secure 256-bit (32-byte) keys using OpenSSL
- Creates compatibility copies for different BC versions (BC210.key, BC220.key, etc.)
- Sets proper file permissions (600) for security
- Backs up existing keys before regeneration
- Verifies SQL Server TLS certificate configuration
- Generates a PowerShell verification script

### Key Locations

The script creates keys in multiple locations for compatibility:

1. **Primary Location**: `/home/bcserver/Keys/bc.key`
2. **Version-Specific**: `/home/bcserver/Keys/BC[version].key`
3. **Service Directory**: `[BC_Service_Directory]/Secret.key`
4. **Wine Paths**: 
   - `$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/[version]/Server/Keys/`

### Configuration

In `CustomSettings.config`:

```xml
<!-- Enable SQL encryption -->
<add key="EnableSqlConnectionEncryption" value="true" />

<!-- Use local key file -->
<add key="EncryptionProvider" value="LocalKeyFile" />
```

## Comparison with PowerShell Implementation

| Feature | PowerShell | Bash |
|---------|------------|------|
| Key Generation | `System.Security.Cryptography.RandomNumberGenerator` | `openssl rand` |
| Key Size | 32 bytes (256-bit) | 32 bytes (256-bit) |
| File Format | Binary | Binary |
| Permissions | Windows ACLs | Unix permissions (600) |
| Verification | BC cmdlets | Custom verification script |

## Security Considerations

1. **Key Storage**: Keys are stored with restrictive permissions (600)
2. **Backup**: Previous keys are automatically backed up with timestamps
3. **Randomness**: OpenSSL provides cryptographically secure random data
4. **SQL TLS**: The script can verify SQL Server certificate configuration

## Troubleshooting

### Verify Key Setup

```bash
# Using the generated PowerShell script
pwsh /home/bcserver/Keys/verify-encryption.ps1

# Manual verification
ls -la /home/bcserver/Keys/
xxd -l 32 /home/bcserver/Keys/bc.key  # Should show 32 random bytes
```

### Common Issues

1. **Permission Denied**: Ensure the script is run with appropriate permissions
2. **OpenSSL Missing**: Install OpenSSL package if not available
3. **SQL Connection Fails**: Check SQL Server TLS/SSL configuration

## Integration with Docker

The encryption setup is automatically handled in the container startup:

1. `entrypoint.sh` checks if encryption key exists
2. If not, runs `setup-bc-encryption.sh`
3. Keys are persisted in the `bc_data` volume

## Testing

Run the test script to verify the implementation:

```bash
./test-encryption-setup.sh
```

This tests:
- Key generation
- File permissions
- Backup functionality
- Compatibility key creation
- Verification script generation