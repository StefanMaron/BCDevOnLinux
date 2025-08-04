#!/usr/bin/env pwsh

# Create BC server configuration template
try {
    Write-Host "Creating BC server configuration template..."
    
    # Ensure directory exists
    $configDir = "/home/bcserver"
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force
        Write-Host "Created directory: $configDir"
    }
    
    # Create configuration template
    $configLines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<configuration>',
        '  <appSettings>',
        '    <add key="DatabaseServer" value="sql" />',
        '    <add key="DatabaseName" value="CRONUS" />',
        '    <add key="DatabaseUserName" value="sa" />',
        '    <add key="DatabasePassword" value="PLACEHOLDER_PASSWORD" />',
        '    <add key="ServerInstance" value="BC210" />',
        '    <add key="ServicesCertificateThumbprint" value="" />',
        '    <add key="SqlConnectionTimeout" value="05:00:00" />',
        '    <add key="DefaultCompany" value="" />',
        '  </appSettings>',
        '</configuration>'
    )
    
    $configTemplate = $configLines -join "`r`n"
    $configTemplate | Out-File -FilePath "/home/bcserver/CustomSettings.config.template" -Encoding utf8
    Write-Host "BC server configuration template created at /home/bcserver/CustomSettings.config.template"
    
    Write-Host "Configuration template setup completed successfully"
    exit 0
    
} catch {
    Write-Error "Failed to create BC configuration template: $_"
    exit 1
}
