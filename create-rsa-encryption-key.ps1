#!/usr/bin/env pwsh

# create-rsa-encryption-key.ps1 - Create RSA encryption key for BC Server LocalKeyFile provider
# This script generates an RSA key pair in XML format that matches New-NAVEncryptionKey output

param(
    [Parameter(Mandatory=$false)]
    [string]$KeyPath = "/home/bcserver/Keys/bc.key",
    
    [Parameter(Mandatory=$false)]
    [int]$KeySize = 2048,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

try {
    Write-Host "Creating RSA encryption key for BC Server LocalKeyFile provider..." -ForegroundColor Green
    Write-Host "This will generate a key in XML format matching New-NAVEncryptionKey" -ForegroundColor Yellow
    
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
    
    Write-Host "Generating $KeySize-bit RSA key pair..." -ForegroundColor Cyan
    
    # Generate RSA key pair using .NET Framework - use RSACryptoServiceProvider for XML compatibility
    $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new($KeySize)
    
    # BC expects the RSA key in XML format exactly like New-NAVEncryptionKey creates
    # Export the complete RSA key (including private key) to XML format
    $rsaKeyXml = $rsa.ToXmlString($true)  # true = include private key
    
    Write-Host "RSA key generated in BC-compatible XML format" -ForegroundColor Green
    Write-Host "Key XML length: $($rsaKeyXml.Length) characters" -ForegroundColor Cyan
    
    # Write the XML directly to the key file (no encryption, matching BC standard)
    [System.IO.File]::WriteAllText($KeyPath, $rsaKeyXml, [System.Text.Encoding]::UTF8)
    
    Write-Host "RSA encryption key created successfully!" -ForegroundColor Green
    Write-Host "Key file: $KeyPath" -ForegroundColor Cyan
    Write-Host "Key size: $KeySize bits" -ForegroundColor Cyan
    Write-Host "Key format: BC-compatible XML (matches New-NAVEncryptionKey)" -ForegroundColor Cyan
    
    # Create compatibility copies for BC
    $secretKeyPath = "$keysDir/Secret.key"
    Copy-Item $KeyPath $secretKeyPath -Force
    Write-Host "Created Secret.key copy at: $secretKeyPath" -ForegroundColor Cyan
    
    # Also create BC.key (the standard BC Server name)
    $bcKeyPath = "$keysDir/BC.key"
    Copy-Item $KeyPath $bcKeyPath -Force
    Write-Host "Created BC.key copy at: $bcKeyPath" -ForegroundColor Cyan
    
    # Cleanup sensitive data
    $rsa.Dispose()
    
    Write-Host "RSA key generation completed successfully!" -ForegroundColor Green
    Write-Host "Key file format matches New-NAVEncryptionKey output" -ForegroundColor Green
    return $true
    
} catch {
    Write-Error "Failed to create RSA encryption key: $_"
    Write-Error $_.ScriptStackTrace
    return $false
}
