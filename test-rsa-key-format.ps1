#!/usr/bin/env pwsh

# test-rsa-key-format.ps1 - Test if our RSA key generation matches BC format

Write-Host "Testing RSA Key Format Compatibility" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host ""

# Create a test key
$testKeyPath = "/tmp/test-bc-rsa.key"
Write-Host "Generating test RSA key..." -ForegroundColor Yellow

$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048)
$rsaKeyXml = $rsa.ToXmlString($true)  # true = include private key
[System.IO.File]::WriteAllText($testKeyPath, $rsaKeyXml, [System.Text.Encoding]::UTF8)
$rsa.Dispose()

Write-Host "✅ Test key generated" -ForegroundColor Green

# Validate format
$generatedXml = [System.IO.File]::ReadAllText($testKeyPath, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "📋 Format Analysis:" -ForegroundColor Cyan
Write-Host "Key length: $($generatedXml.Length) characters" -ForegroundColor White
Write-Host "Starts with: $($generatedXml.Substring(0, 50))..." -ForegroundColor White
Write-Host "Contains required elements:" -ForegroundColor White

$requiredElements = @("Modulus", "Exponent", "P", "Q", "DP", "DQ", "InverseQ", "D")
foreach ($element in $requiredElements) {
    $contains = $generatedXml.Contains("<$element>")
    $status = if ($contains) { "✅" } else { "❌" }
    Write-Host "  $status $element" -ForegroundColor $(if ($contains) { "Green" } else { "Red" })
}

# Test encryption/decryption
Write-Host ""
Write-Host "🔐 Testing Password Encryption:" -ForegroundColor Cyan
$testPassword = "TestPassword123!"

$rsaTest = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
$rsaTest.FromXmlString($generatedXml)

$passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($testPassword)
$encryptedPassword = $rsaTest.Encrypt($passwordBytes, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA1)
$base64EncryptedPassword = [Convert]::ToBase64String($encryptedPassword)

Write-Host "Test password: $testPassword" -ForegroundColor White
Write-Host "Encrypted length: $($base64EncryptedPassword.Length) characters" -ForegroundColor White
Write-Host "Encrypted value: $($base64EncryptedPassword.Substring(0, 50))..." -ForegroundColor White

# Test decryption
$decryptedBytes = $rsaTest.Decrypt($encryptedPassword, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA1)
$decryptedPassword = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)

if ($decryptedPassword -eq $testPassword) {
    Write-Host "✅ Encryption/decryption test PASSED" -ForegroundColor Green
} else {
    Write-Host "❌ Encryption/decryption test FAILED" -ForegroundColor Red
}

$rsaTest.Dispose()

Write-Host ""
Write-Host "🎯 Format Comparison:" -ForegroundColor Cyan
Write-Host "Expected BC format: <RSAKeyValue><Modulus>...</Modulus><Exponent>...</Exponent>..." -ForegroundColor White
Write-Host "Generated format:   $($generatedXml.Substring(0, 80))..." -ForegroundColor White

if ($generatedXml.StartsWith("<RSAKeyValue>") -and $generatedXml.EndsWith("</RSAKeyValue>")) {
    Write-Host "✅ Format matches BC standard!" -ForegroundColor Green
} else {
    Write-Host "❌ Format does not match BC standard" -ForegroundColor Red
}

# Cleanup
Remove-Item $testKeyPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "✅ RSA key format test completed!" -ForegroundColor Green
