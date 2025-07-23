#!/usr/bin/env pwsh

# Create encryption key for BC Server (BC4Ubuntu approach)
try {
    Write-Host "Creating BC Server encryption key..."
    
    # Ensure Keys directory exists
    $keysDir = "/home/bcserver/Keys"
    if (-not (Test-Path $keysDir)) {
        New-Item -Path $keysDir -ItemType Directory -Force
        Write-Host "Created keys directory: $keysDir"
    }
    
    # Generate a 256-bit (32 byte) encryption key
    $key = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($key)
    
    # Save the key to file (BC4Ubuntu uses bc.key)
    $keyPath = "$keysDir/bc.key"
    [System.IO.File]::WriteAllBytes($keyPath, $key)
    
    Write-Host "Encryption key created at: $keyPath"
    Write-Host "Key generation completed successfully"
    
    exit 0
    
} catch {
    Write-Error "Failed to create encryption key: $_"
    exit 1
}
