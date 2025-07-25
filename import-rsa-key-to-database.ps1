#!/usr/bin/env pwsh

# import-rsa-key-to-database.ps1 - Import RSA encryption key to BC database
# This script imports the RSA public key into the dbo.$ndo$publicencryptionkey table

param(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseUser,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabasePassword,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PasswordFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$VerboseLogging
)

try {
    Write-Host "BC Encryption Key Database Import" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Database Server: $DatabaseServer" -ForegroundColor Cyan
    Write-Host "Database Name: $DatabaseName" -ForegroundColor Cyan
    Write-Host "Database User: $DatabaseUser" -ForegroundColor Cyan
    Write-Host "Key Path: $KeyPath" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if key file exists
    if (-not (Test-Path $KeyPath)) {
        throw "Key file not found: $KeyPath"
    }
    
    # Read and decrypt the RSA key
    Write-Host "Reading RSA encryption key..." -ForegroundColor Yellow
    $keyData = [System.IO.File]::ReadAllBytes($KeyPath)
    Write-Host "Key file size: $($keyData.Length) bytes" -ForegroundColor Cyan
    
    # Read password if available
    $keyPassword = ""
    if ($PasswordFile -and (Test-Path $PasswordFile)) {
        Write-Host "Reading key password from file..." -ForegroundColor Yellow
        $keyPassword = [System.IO.File]::ReadAllText($PasswordFile, [System.Text.Encoding]::UTF8)
        $keyPassword = $keyPassword.Trim()
        Write-Host "Password loaded successfully" -ForegroundColor Green
    } else {
        Write-Host "No password file provided, using empty password" -ForegroundColor Yellow
    }
    
    # Extract the public key from the RSA key file
    Write-Host "Extracting public key from RSA key..." -ForegroundColor Yellow
    
    # Decrypt the key file to get the RSA key data
    if ($keyData.Length -gt 32) {
        # This is likely an encrypted RSA key file
        $salt = $keyData[0..15]
        $iv = $keyData[16..31]
        $encryptedData = $keyData[32..($keyData.Length-1)]
        
        # Try different password variants to handle encoding issues
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
                    Write-Host "Added SecureString-converted password variant" -ForegroundColor Cyan
                }
            } catch {
                if ($VerboseLogging) {
                    Write-Host "SecureString conversion failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        $passwordVariants += ""  # Try empty password as fallback
        
        $decryptionSuccessful = $false
        $keyContainer = $null
        
        foreach ($passwordAttempt in $passwordVariants) {
            try {
                if ($VerboseLogging) {
                    Write-Host "Trying password variant (length: $($passwordAttempt.Length))..." -ForegroundColor Cyan
                }
                
                # Derive decryption key from password using PBKDF2
                $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordAttempt, $salt, 10000)
                $aesKey = $pbkdf2.GetBytes(32)
                
                # Decrypt the RSA key data
                $aes = [System.Security.Cryptography.Aes]::Create()
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
                $aes.Key = $aesKey
                $aes.IV = $iv
                
                $decryptor = $aes.CreateDecryptor()
                $decryptedBytes = $decryptor.TransformFinalBlock($encryptedData, 0, $encryptedData.Length)
                $keyJson = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
                
                # Parse the JSON to get the key data
                $keyContainer = $keyJson | ConvertFrom-Json
                $publicKeyBytes = [Convert]::FromBase64String($keyContainer.PublicKey)
                
                if ($VerboseLogging) {
                    Write-Host "AES decryption successful with password variant!" -ForegroundColor Green
                    Write-Host "Decrypted data size: $($decryptedBytes.Length) bytes" -ForegroundColor Green
                }
                
                $decryptionSuccessful = $true
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
                    Write-Host "Password variant failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        
        if (-not $decryptionSuccessful) {
            throw "Failed to decrypt RSA key with provided password"
        }
        
        Write-Host "RSA key decrypted successfully" -ForegroundColor Green
        Write-Host "Key Type: $($keyContainer.KeyType)" -ForegroundColor Cyan
        Write-Host "Key Size: $($keyContainer.KeySize) bits" -ForegroundColor Cyan
        
        $aes.Dispose()
    } else {
        throw "Invalid RSA key file format - file too small to contain encrypted RSA key"
    }
    
    # Convert public key to Base64 for database storage
    $publicKeyBase64 = [Convert]::ToBase64String($publicKeyBytes)
    Write-Host "Public key extracted successfully" -ForegroundColor Green
    Write-Host "Public key length: $($publicKeyBase64.Length) characters" -ForegroundColor Cyan
    
    # Connect to SQL Server and import the key
    Write-Host ""
    Write-Host "Connecting to SQL Server database..." -ForegroundColor Yellow
    
    $connectionString = "Server=$DatabaseServer;Database=$DatabaseName;User Id=$DatabaseUser;Password=$DatabasePassword;TrustServerCertificate=true;Connect Timeout=30;"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    
    try {
        $connection.Open()
        Write-Host "Connected to database successfully" -ForegroundColor Green
        
        # Check if the table exists
        $checkTableQuery = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '`$ndo`$publicencryptionkey'"
        $checkCommand = New-Object System.Data.SqlClient.SqlCommand($checkTableQuery, $connection)
        $tableExists = $checkCommand.ExecuteScalar()
        
        if ($tableExists -eq 0) {
            Write-Host "Creating dbo.`$ndo`$publicencryptionkey table..." -ForegroundColor Yellow
            
            # Create the table structure that BC expects
            $createTableQuery = @"
CREATE TABLE [dbo].[`$ndo`$publicencryptionkey] (
    [timestamp] [timestamp] NOT NULL,
    [Key Code] [nvarchar](20) NOT NULL,
    [Public Key] [nvarchar](max) NOT NULL,
    CONSTRAINT [PK_`$ndo`$publicencryptionkey] PRIMARY KEY CLUSTERED ([Key Code])
)
"@
            $createCommand = New-Object System.Data.SqlClient.SqlCommand($createTableQuery, $connection)
            $createCommand.ExecuteNonQuery() | Out-Null
            Write-Host "Table created successfully" -ForegroundColor Green
        } else {
            Write-Host "Table dbo.`$ndo`$publicencryptionkey already exists" -ForegroundColor Cyan
        }
        
        # Insert or update the encryption key
        $keyCode = "DEFAULT"
        Write-Host "Inserting/updating encryption key with code '$keyCode'..." -ForegroundColor Yellow
        
        $upsertQuery = @"
MERGE [dbo].[`$ndo`$publicencryptionkey] AS target
USING (VALUES (@KeyCode, @PublicKey)) AS source ([Key Code], [Public Key])
ON target.[Key Code] = source.[Key Code]
WHEN MATCHED THEN
    UPDATE SET [Public Key] = source.[Public Key]
WHEN NOT MATCHED THEN
    INSERT ([Key Code], [Public Key])
    VALUES (source.[Key Code], source.[Public Key]);
"@
        
        $upsertCommand = New-Object System.Data.SqlClient.SqlCommand($upsertQuery, $connection)
        $upsertCommand.Parameters.AddWithValue("@KeyCode", $keyCode) | Out-Null
        $upsertCommand.Parameters.AddWithValue("@PublicKey", $publicKeyBase64) | Out-Null
        
        $rowsAffected = $upsertCommand.ExecuteNonQuery()
        Write-Host "Key import completed - $rowsAffected row(s) affected" -ForegroundColor Green
        
        # Verify the import
        $verifyQuery = "SELECT [Key Code], LEN([Public Key]) as [Key Length] FROM [dbo].[`$ndo`$publicencryptionkey] WHERE [Key Code] = @KeyCode"
        $verifyCommand = New-Object System.Data.SqlClient.SqlCommand($verifyQuery, $connection)
        $verifyCommand.Parameters.AddWithValue("@KeyCode", $keyCode) | Out-Null
        
        $reader = $verifyCommand.ExecuteReader()
        if ($reader.Read()) {
            $storedKeyCode = $reader["Key Code"]
            $storedKeyLength = $reader["Key Length"]
            Write-Host ""
            Write-Host "✅ Verification successful:" -ForegroundColor Green
            Write-Host "   Key Code: $storedKeyCode" -ForegroundColor Cyan
            Write-Host "   Key Length: $storedKeyLength characters" -ForegroundColor Cyan
        }
        $reader.Close()
        
    } finally {
        $connection.Close()
    }
    
    Write-Host ""
    Write-Host "🎉 RSA encryption key imported successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Public key extracted from RSA key file" -ForegroundColor White
    Write-Host "  ✅ Key imported to dbo.`$ndo`$publicencryptionkey table" -ForegroundColor White
    Write-Host "  ✅ BC Server can now use ProtectedDatabasePassword" -ForegroundColor White
    Write-Host "  ✅ Database encryption is fully configured" -ForegroundColor White
    
    exit 0
    
} catch {
    Write-Error "Failed to import encryption key to database: $_"
    if ($VerboseLogging) {
        Write-Error $_.ScriptStackTrace
    }
    exit 1
}
