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
    
    # Read the RSA key file - now in XML format like New-NAVEncryptionKey creates
    $rsaKeyXml = [System.IO.File]::ReadAllText($KeyPath, [System.Text.Encoding]::UTF8)
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("Key file size: $($keyFileInfo.Length) bytes")
        [Console]::Error.WriteLine("Key content length: $($rsaKeyXml.Length) characters")
        [Console]::Error.WriteLine("Key format: XML (BC standard)")
        
        # Validate XML format
        if ($rsaKeyXml.StartsWith("<RSAKeyValue>") -and $rsaKeyXml.EndsWith("</RSAKeyValue>")) {
            [Console]::Error.WriteLine("✅ Valid RSA XML format detected")
        } else {
            [Console]::Error.WriteLine("❌ Invalid RSA XML format - expected <RSAKeyValue>...</RSAKeyValue>")
        }
    }
    
    # Validate this is a BC-compatible RSA key in XML format
    if (-not $rsaKeyXml.StartsWith("<RSAKeyValue>")) {
        throw "Invalid RSA key format - expected XML format like New-NAVEncryptionKey creates. Got: $($rsaKeyXml.Substring(0, [Math]::Min(50, $rsaKeyXml.Length)))..."
    }
    
    if ($VerboseLogging) {
        [Console]::Error.WriteLine("RSA key loaded successfully from XML format")
    }
        
    # Load the RSA key from XML format (no password needed since it's stored as plain XML)
    $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    
    try {
        # Import the RSA key from XML format
        $rsa.FromXmlString($rsaKeyXml)
        
        if ($VerboseLogging) {
            [Console]::Error.WriteLine("RSA key imported successfully from XML")
            [Console]::Error.WriteLine("Key size: $($rsa.KeySize) bits")
        }
        
    } catch {
        throw "Failed to load RSA key from XML format: $($_.Exception.Message)"
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
    
    # Cleanup
    $rsa.Dispose()
    
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
