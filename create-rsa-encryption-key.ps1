#!/usr/bin/env pwsh

# create-rsa-encryption-key.ps1 - Create RSA encryption key for BC Server LocalKeyFile provider
# This script generates an RSA key pair that can be used with BC's native encryption provider

param(
    [Parameter(Mandatory=$false)]
    [string]$KeyPath = "/home/bcserver/Keys/bc.key",
    
    [Parameter(Mandatory=$false)]
    [int]$KeySize = 2048,
    
    [Parameter(Mandatory=$false)]
    [securestring]$Password,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

try {
    Write-Host "Creating RSA encryption key for BC Server LocalKeyFile provider..." -ForegroundColor Green
    
    # Create keys directory if it doesn't exist
    $keysDir = Split-Path $KeyPath -Parent
    if (-not (Test-Path $keysDir)) {
        New-Item -Path $keysDir -ItemType Directory -Force | Out-Null
        Write-Host "Created keys directory: $keysDir" -ForegroundColor Yellow
    }
    
    # Check if key already exists
    if ((Test-Path $KeyPath) -and -not $Force) {
        Write-Host "Key already exists at: $KeyPath" -ForegroundColor Yellow
        Write-Host "Use -Force parameter to overwrite existing key" -ForegroundColor Yellow
        return
    }
    
    # If no password provided, generate a secure random password
    if (-not $Password) {
        Write-Host "Generating secure password for RSA key..." -ForegroundColor Cyan
        $randomBytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($randomBytes)
        $passwordString = [Convert]::ToBase64String($randomBytes)
        $Password = ConvertTo-SecureString -String $passwordString -AsPlainText -Force
        
        # Save password to a separate file for reference
        $passwordFile = "$keysDir/bc-key-password.txt"
        $passwordString | Out-File -FilePath $passwordFile -Encoding UTF8
        Write-Host "Password saved to: $passwordFile" -ForegroundColor Yellow
        Write-Host "IMPORTANT: Keep this password file secure and backed up!" -ForegroundColor Red
    }
    
    Write-Host "Generating $KeySize-bit RSA key pair..." -ForegroundColor Cyan
    
    # Generate RSA key pair using .NET Framework
    $rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
    
    # Export private key as PKCS#8 format (compatible with BC)
    $privateKeyBytes = $rsa.ExportRSAPrivateKey()
    
    # Create a simple container format that BC can read
    # BC expects a specific format for its RSA keys
    $keyContainer = @{
        KeyType = "RSA"
        KeySize = $KeySize
        PrivateKey = [Convert]::ToBase64String($privateKeyBytes)
        PublicKey = [Convert]::ToBase64String($rsa.ExportRSAPublicKey())
        Created = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    }
    
    # Serialize and encrypt the key data
    $keyJson = $keyContainer | ConvertTo-Json -Compress
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyJson)
    
    # Use AES to encrypt the RSA key with the provided password
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    
    # Derive key from password using PBKDF2
    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($salt)
    
    $passwordString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordString, $salt, 10000)
    $aes.Key = $pbkdf2.GetBytes(32) # 256-bit key
    $aes.GenerateIV()
    
    # Encrypt the key data
    $encryptor = $aes.CreateEncryptor()
    $encryptedData = $encryptor.TransformFinalBlock($keyBytes, 0, $keyBytes.Length)
    
    # Create final key file format: Salt (16) + IV (16) + EncryptedData
    $finalKeyData = $salt + $aes.IV + $encryptedData
    
    # Write to file
    [System.IO.File]::WriteAllBytes($KeyPath, $finalKeyData)
    
    # Set restrictive permissions
    if ($IsLinux) {
        & chmod 600 $KeyPath
    }
    
    Write-Host "RSA encryption key created successfully!" -ForegroundColor Green
    Write-Host "Key file: $KeyPath" -ForegroundColor Cyan
    Write-Host "Key size: $KeySize bits" -ForegroundColor Cyan
    Write-Host "Key file size: $($finalKeyData.Length) bytes" -ForegroundColor Cyan
    
    # Create compatibility copies for BC
    $secretKeyPath = "$keysDir/Secret.key"
    Copy-Item $KeyPath $secretKeyPath -Force
    if ($IsLinux) {
        & chmod 600 $secretKeyPath
    }
    Write-Host "Created Secret.key copy at: $secretKeyPath" -ForegroundColor Cyan
    
    # Cleanup sensitive data
    $aes.Dispose()
    $rsa.Dispose()
    $passwordString = $null
    [System.GC]::Collect()
    
    Write-Host "RSA key generation completed successfully!" -ForegroundColor Green
    return $true
    
} catch {
    Write-Error "Failed to create RSA encryption key: $_"
    Write-Error $_.ScriptStackTrace
    return $false
}
