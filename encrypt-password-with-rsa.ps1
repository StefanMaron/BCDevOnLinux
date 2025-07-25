#!/usr/bin/env pwsh

# encrypt-password-with-rsa.ps1 - Encrypt database password using RSA key for BC ProtectedDatabasePassword
# This script encrypts a password using an RSA key that BC Server can decrypt using its LocalKeyFile provider

param(
    [Parameter(Mandatory=$true)]
    [string]$Password,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PasswordFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$VerboseLogging
)

try {
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Encrypting password with RSA key for BC ProtectedDatabasePassword...")
        [Console]::Error.WriteLine("Parameters received:")
        [Console]::Error.WriteLine("  Password: $($Password -ne $null -and $Password.Length -gt 0)")
        [Console]::Error.WriteLine("  KeyPath: $KeyPath")
        [Console]::Error.WriteLine("  PasswordFile: $PasswordFile")
    }
    
    # Validate key file exists
    if (-not (Test-Path $KeyPath)) {
        throw "RSA key file not found: $KeyPath"
    }
    
    # Get file metadata to check for caching issues
    $keyFileInfo = Get-Item $KeyPath
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Key file metadata:")
        [Console]::Error.WriteLine("  Path: $($keyFileInfo.FullName)")
        [Console]::Error.WriteLine("  Size: $($keyFileInfo.Length) bytes")
        [Console]::Error.WriteLine("  Created: $($keyFileInfo.CreationTime)")
        [Console]::Error.WriteLine("  Modified: $($keyFileInfo.LastWriteTime)")
        [Console]::Error.WriteLine("  Accessed: $($keyFileInfo.LastAccessTime)")
    }
    
    # Force fresh read of the key file (avoid any potential caching)
    [System.GC]::Collect()  # Force garbage collection first
    Start-Sleep -Milliseconds 100  # Brief pause to ensure file system consistency
    
    # Read the RSA key file with explicit fresh read
    $keyData = [System.IO.File]::ReadAllBytes($KeyPath)
    
    # The key file format: Salt(16) + IV(16) + EncryptedRSAKey
    if ($keyData.Length -lt 32) {
        throw "Invalid key file format - file too small (expected > 32 bytes, got $($keyData.Length))"
    }
    
    $salt = $keyData[0..15]
    $iv = $keyData[16..31] 
    $encryptedRSAKeyData = $keyData[32..($keyData.Length-1)]
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Key file size: $($keyData.Length) bytes")
        [Console]::Error.WriteLine("Encrypted RSA key data size: $($encryptedRSAKeyData.Length) bytes")
        
        # Check for potential key/password file timestamp mismatch (caching issue indicator)
        if ($PasswordFile -and (Test-Path $PasswordFile)) {
            $keyTime = (Get-Item $KeyPath).LastWriteTime
            $passwordTime = (Get-Item $PasswordFile).LastWriteTime
            $timeDiff = [Math]::Abs(($keyTime - $passwordTime).TotalSeconds)
            
            [Console]::Error.WriteLine("Key file timestamp: $keyTime")
            [Console]::Error.WriteLine("Password file timestamp: $passwordTime")
            [Console]::Error.WriteLine("Time difference: $timeDiff seconds")
            
            if ($timeDiff -gt 60) {
                [Console]::Error.WriteLine("WARNING: Key and password files have significant time difference - possible caching issue!")
            }
        }
        
        # Show salt and IV for debugging
        [Console]::Error.WriteLine("Salt (first 8 bytes): $([Convert]::ToHexString($salt[0..7]))")
        [Console]::Error.WriteLine("IV (first 8 bytes): $([Convert]::ToHexString($iv[0..7]))")
    }
    
    # Read the key password
    $keyPassword = ""
    if ($PasswordFile -and (Test-Path $PasswordFile)) {
        # Force fresh read of password file (avoid caching)
        [System.GC]::Collect()
        Start-Sleep -Milliseconds 50
        
        $passwordFileInfo = Get-Item $PasswordFile
        if ($VerboseLogging) {
            [Console]::Error.WriteLine("Password file metadata:")
            [Console]::Error.WriteLine("  Path: $($passwordFileInfo.FullName)")
            [Console]::Error.WriteLine("  Size: $($passwordFileInfo.Length) bytes")
            [Console]::Error.WriteLine("  Created: $($passwordFileInfo.CreationTime)")
            [Console]::Error.WriteLine("  Modified: $($passwordFileInfo.LastWriteTime)")
        }
        
        # Read password with explicit encoding to avoid caching/encoding issues
        $keyPassword = [System.IO.File]::ReadAllText($PasswordFile, [System.Text.Encoding]::UTF8)
        $keyPassword = $keyPassword.Trim()
        
        if ($VerboseLogging) {
            [Console]::Error.WriteLine("Using key password from file: $PasswordFile")
            [Console]::Error.WriteLine("Password file size: $($passwordFileInfo.Length) bytes")
            [Console]::Error.WriteLine("Password length: $($keyPassword.Length) characters")
            [Console]::Error.WriteLine("Password starts with: $($keyPassword.Substring(0, [Math]::Min(8, $keyPassword.Length)))...")
        }
    } else {
        if ($VerboseLogging) {
            [Console]::Error.WriteLine("No key password file found, trying without password")
        }
    }
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Attempting to derive decryption key using PBKDF2...")
        [Console]::Error.WriteLine("Testing different password encoding methods...")
    }
    
    # The key creation script uses Marshal.PtrToStringAuto() to convert SecureString to string
    # We need to try both the direct password and potential encoding variations
    
    $passwordVariants = @()
    if ($keyPassword) {
        # The key is encrypted using the raw password string (not the SecureString conversion)
        # Since the password file contains the original Base64 string that was used to create the SecureString,
        # we should use it directly for PBKDF2 derivation
        $passwordVariants += $keyPassword.Trim()
        $passwordVariants += $keyPassword.TrimEnd("`r", "`n", " ", "`t")
        $passwordVariants += $keyPassword
        
        # Also try the SecureString round-trip in case that's what was actually used
        try {
            $securePassword = ConvertTo-SecureString -String $keyPassword.Trim() -AsPlainText -Force
            $marshalPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
            $passwordVariants += $marshalPassword
            if ($VerboseLogging) {
                [Console]::Error.WriteLine("Added SecureString-converted password variant")
            }
        } catch {
            if ($VerboseLogging) {
                [Console]::Error.WriteLine("SecureString conversion failed: $($_.Exception.Message)")
            }
        }
    }
    $passwordVariants += ""  # Try empty password as last resort
    
    $decryptionSuccessful = $false
    $decryptedKeyData = $null
    
    foreach ($passwordAttempt in $passwordVariants) {
        try {
            if ($VerboseLogging) {
                [Console]::Error.WriteLine("Trying password variant (length: $($passwordAttempt.Length))...")
            }
            
            # Derive decryption key from password using PBKDF2 (same as key creation)
            $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordAttempt, $salt, 10000)
            $aesKey = $pbkdf2.GetBytes(32) # 256-bit key
            
            # Decrypt the RSA key data
            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = $aesKey
            $aes.IV = $iv
            
            $decryptor = $aes.CreateDecryptor()
            $decryptedKeyData = $decryptor.TransformFinalBlock($encryptedRSAKeyData, 0, $encryptedRSAKeyData.Length)
            
            if ($VerboseLogging) {
                [Console]::Error.WriteLine("AES decryption successful with password variant!")
                [Console]::Error.WriteLine("Decrypted data size: $($decryptedKeyData.Length) bytes")
            }
            
            $decryptionSuccessful = $true
            
            # Clean up
            $aes.Dispose()
            $pbkdf2.Dispose()
            $decryptor.Dispose()
            break
            
        } catch {
            # Clean up and try next password variant
            if ($aes) { $aes.Dispose() }
            if ($pbkdf2) { $pbkdf2.Dispose() }
            if ($decryptor) { $decryptor.Dispose() }
            
            if ($VerboseLogging) {
                [Console]::Error.WriteLine("Password variant failed: $($_.Exception.Message)")
            }
        }
    }
    
    if (-not $decryptionSuccessful) {
        # Before giving up, try one more approach - check if this is a caching issue
        # by attempting to regenerate the password from the original key creation logic
        if ($VerboseLogging) {
            [Console]::Error.WriteLine("All password variants failed. Checking for potential key-password mismatch...")
            [Console]::Error.WriteLine("This could indicate a container caching issue where the key and password were created in different instances.")
        }
        
        throw "Failed to decrypt RSA key with any password variant. This appears to be a key-password mismatch, possibly due to container caching. The key file and password file may have been created in different container instances or builds."
    }
    
    # Parse the decrypted JSON containing the RSA key
    $keyJson = [System.Text.Encoding]::UTF8.GetString($decryptedKeyData)
    $keyContainer = $keyJson | ConvertFrom-Json
    
    if ($keyContainer.KeyType -ne "RSA") {
        throw "Invalid key type: $($keyContainer.KeyType) (expected RSA)"
    }
    
    # Reconstruct the RSA key from the stored data
    $privateKeyBytes = [Convert]::FromBase64String($keyContainer.PrivateKey)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    
    # Import the private key - use correct method signature
    try {
        $rsa.ImportRSAPrivateKey($privateKeyBytes, [ref]$null)
    } catch {
        # Try alternative import method for compatibility
        $rsa.ImportRSAPrivateKey([System.ReadOnlySpan[byte]]::new($privateKeyBytes))
    }
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("RSA key loaded successfully (Key size: $($keyContainer.KeySize) bits)")
    }
    
    # Encrypt the password using RSA OAEP padding (BC standard)
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    
    # BC Server typically uses OAEP with SHA-1 for compatibility
    $encryptedPassword = $rsa.Encrypt($passwordBytes, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA1)
    
    # Convert to Base64 for BC configuration
    $base64EncryptedPassword = [Convert]::ToBase64String($encryptedPassword)
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Password encrypted successfully")
        [Console]::Error.WriteLine("Encrypted password length: $($base64EncryptedPassword.Length) characters")
    }
    
    # Output the encrypted password
    Write-Output $base64EncryptedPassword
    
    # Cleanup sensitive data
    $aes.Dispose()
    $rsa.Dispose()
    $pbkdf2.Dispose()
    
    # Clear sensitive variables
    $passwordBytes = $null
    $keyPassword = $null
    $privateKeyBytes = $null
    $decryptedKeyData = $null
    
    # Force garbage collection
    [System.GC]::Collect()
    
    exit 0
    
} catch {
    $errorMessage = "Failed to encrypt password with RSA key: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    # Add detailed debugging information
    Write-Host "DEBUG: Password provided: $($Password -ne $null -and $Password.Length -gt 0)" -ForegroundColor Red
    Write-Host "DEBUG: Key path: $KeyPath" -ForegroundColor Red
    Write-Host "DEBUG: Key file exists: $(Test-Path $KeyPath)" -ForegroundColor Red
    Write-Host "DEBUG: Password file: $PasswordFile" -ForegroundColor Red
    Write-Host "DEBUG: Password file exists: $(if ($PasswordFile) { Test-Path $PasswordFile } else { 'N/A' })" -ForegroundColor Red
    
    if ($VerboseLogging) {
        Write-Error $_.ScriptStackTrace
    }
    
    # Also output error to stderr for bash script to capture
    [Console]::Error.WriteLine("ENCRYPT_ERROR: $errorMessage")
    
    exit 1
}
