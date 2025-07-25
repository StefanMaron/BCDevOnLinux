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
    
    # Read the RSA key from XML format (like New-NAVEncryptionKey creates)
    Write-Host "Reading RSA encryption key..." -ForegroundColor Yellow
    $rsaKeyXml = [System.IO.File]::ReadAllText($KeyPath, [System.Text.Encoding]::UTF8)
    
    Write-Host "Key file format: BC-compatible XML" -ForegroundColor Cyan
    Write-Host "Key XML length: $($rsaKeyXml.Length) characters" -ForegroundColor Cyan
    
    # Validate this is a BC-compatible RSA key in XML format
    if (-not $rsaKeyXml.StartsWith("<RSAKeyValue>")) {
        throw "Invalid RSA key format - expected XML format like New-NAVEncryptionKey creates"
    }
    
    Write-Host "✅ Valid BC RSA key format detected" -ForegroundColor Green
    # Load the RSA key from XML and extract public key for database storage
    Write-Host "Loading RSA key from XML format..." -ForegroundColor Yellow
    
    $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    try {
        # Load the complete RSA key from XML
        $rsa.FromXmlString($rsaKeyXml)
        Write-Host "RSA key loaded successfully" -ForegroundColor Green
        Write-Host "Key size: $($rsa.KeySize) bits" -ForegroundColor Cyan
        
        # Extract public key only for database storage
        $publicKeyXml = $rsa.ToXmlString($false)  # false = public key only
        Write-Host "Public key extracted for database storage" -ForegroundColor Green
        Write-Host "Public key XML length: $($publicKeyXml.Length) characters" -ForegroundColor Cyan
        
    } catch {
        throw "Failed to load RSA key from XML: $($_.Exception.Message)"
    } finally {
        $rsa.Dispose()
    }
    
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
CREATE TABLE [dbo].[`$ndo`$publicencryptionkey](
    [id] [int] NOT NULL,
    [publickey] [nvarchar](512) NULL,
    CONSTRAINT [PK`$`$ndo`$publicencryptionkey] PRIMARY KEY CLUSTERED ([id] ASC)
    WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
"@
            $createCommand = New-Object System.Data.SqlClient.SqlCommand($createTableQuery, $connection)
            $createCommand.ExecuteNonQuery() | Out-Null
            Write-Host "Table created successfully" -ForegroundColor Green
        } else {
            Write-Host "Table dbo.`$ndo`$publicencryptionkey already exists" -ForegroundColor Cyan
        }
        
        # Insert or update the encryption key
        $keyId = 1  # Use ID 1 as the default key
        Write-Host "Inserting/updating encryption key with ID '$keyId'..." -ForegroundColor Yellow
        
        $upsertQuery = @"
MERGE [dbo].[`$ndo`$publicencryptionkey] AS target
USING (VALUES (@KeyId, @PublicKey)) AS source ([id], [publickey])
ON target.[id] = source.[id]
WHEN MATCHED THEN
    UPDATE SET [publickey] = source.[publickey]
WHEN NOT MATCHED THEN
    INSERT ([id], [publickey])
    VALUES (source.[id], source.[publickey]);
"@
        
        $upsertCommand = New-Object System.Data.SqlClient.SqlCommand($upsertQuery, $connection)
        $upsertCommand.Parameters.AddWithValue("@KeyId", $keyId) | Out-Null
        $upsertCommand.Parameters.AddWithValue("@PublicKey", $publicKeyXml) | Out-Null
        
        $rowsAffected = $upsertCommand.ExecuteNonQuery()
        Write-Host "Key import completed - $rowsAffected row(s) affected" -ForegroundColor Green
        
        # Verify the import
        $verifyQuery = "SELECT [id], LEN([publickey]) as [Key Length] FROM [dbo].[`$ndo`$publicencryptionkey] WHERE [id] = @KeyId"
        $verifyCommand = New-Object System.Data.SqlClient.SqlCommand($verifyQuery, $connection)
        $verifyCommand.Parameters.AddWithValue("@KeyId", $keyId) | Out-Null
        
        $reader = $verifyCommand.ExecuteReader()
        if ($reader.Read()) {
            $storedKeyId = $reader["id"]
            $storedKeyLength = $reader["Key Length"]
            Write-Host ""
            Write-Host "✅ Verification successful:" -ForegroundColor Green
            Write-Host "   Key ID: $storedKeyId" -ForegroundColor Cyan
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
    Write-Host "  ✅ Key converted to XML format for BC compatibility" -ForegroundColor White
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
