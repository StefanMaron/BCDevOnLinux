#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Creates a Business Central user with NavUserPassword authentication
.DESCRIPTION
    Simplified user creation script based on NavContainerHelper patterns.
    Creates a user in Business Central with the specified credentials and permissions.
.PARAMETER Username
    The username for the new BC user
.PARAMETER Password
    The password for the new BC user (uses SA_PASSWORD if not specified)
.PARAMETER PermissionSetId
    The permission set to assign (default: SUPER)
.PARAMETER ServerInstance
    The BC server instance name (default: BC)
.PARAMETER Tenant
    The tenant ID (default: default)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password = $env:SA_PASSWORD,
    
    [Parameter(Mandatory=$false)]
    [string]$PermissionSetId = "SUPER",
    
    [Parameter(Mandatory=$false)]
    [string]$ServerInstance = "BC",
    
    [Parameter(Mandatory=$false)]
    [string]$Tenant = "default"
)

# Ensure we have a password
if ([string]::IsNullOrEmpty($Password)) {
    $Password = "P@ssw0rd123!"
    Write-Warning "No password specified and SA_PASSWORD not set. Using default password: $Password"
}

Write-Host "Creating Business Central user: $Username" -ForegroundColor Green

try {
    # Find BC management module in artifacts (dynamic version detection)
    $bcArtifactsPath = "/home/bcartifacts/ServiceTier/program files/Microsoft Dynamics NAV"
    $bcVersionDir = Get-ChildItem -Path $bcArtifactsPath -Directory | Sort-Object Name -Descending | Select-Object -First 1
    
    if ($null -eq $bcVersionDir) {
        throw "No BC version directory found in $bcArtifactsPath"
    }
    
    $moduleDir = Join-Path $bcVersionDir.FullName "Service"
    $modulePath = Join-Path $moduleDir "Microsoft.Dynamics.Nav.Management.psm1"
    
    Write-Host "Using BC version: $($bcVersionDir.Name)" -ForegroundColor Cyan
    Write-Host "Loading module from: $modulePath" -ForegroundColor Cyan
    
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    } else {
        # Fallback to try global module
        Write-Warning "Module not found at $modulePath, trying global module..."
        Import-Module Microsoft.Dynamics.Nav.Management -Force
    }
    
    # Create global pwsh.exe wrapper to fix PowerShell spawning issues
    $pwshExeWrapper = "/usr/local/bin/pwsh.exe"
    
    if (-not (Test-Path $pwshExeWrapper)) {
        Write-Host "Creating global pwsh.exe wrapper..." -ForegroundColor Yellow
        
        # Create a bash wrapper script that Wine can execute
        $wrapperScript = @"
#!/bin/bash
exec /usr/bin/pwsh `$@
"@
        
        try {
            # Use bash to create the wrapper
            bash -c "echo '$wrapperScript' > '$pwshExeWrapper' && chmod +x '$pwshExeWrapper'"
            Write-Host "Global pwsh.exe wrapper created at: $pwshExeWrapper" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create global pwsh.exe wrapper"
        }
    }
    
    # Also create Wine-specific locations
    $wineLocations = @(
        "$env:WINEPREFIX/drive_c/windows/system32",
        "$env:WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$($bcVersionDir.Name)/Service"
    )
    
    foreach ($location in $wineLocations) {
        $pwshExePath = "$location/pwsh.exe"
        
        if (-not (Test-Path $pwshExePath)) {
            Write-Host "Creating pwsh.exe at: $location" -ForegroundColor Yellow
            
            # Ensure the directory exists
            if (-not (Test-Path $location)) {
                New-Item -ItemType Directory -Path $location -Force | Out-Null
            }
            
            # Use the global wrapper
            try {
                bash -c "ln -sf '$pwshExeWrapper' '$pwshExePath'"
                Write-Host "pwsh.exe linked to global wrapper at: $pwshExePath" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to link pwsh.exe at $location"
            }
        }
    }
    
    # Ensure Wine PATH includes system32 directory
    $currentPath = wine reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2>/dev/null
    if ($currentPath -notmatch "system32") {
        Write-Host "Adding system32 to Wine PATH..." -ForegroundColor Yellow
        wine reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t REG_EXPAND_SZ /d "%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\system32\wbem;%SystemRoot%\system32\WindowsPowershell\v1.0;C:\Program Files\dotnet" /f 2>/dev/null
    }
    
    # Create the user
    Write-Host "Creating user account..." -ForegroundColor Yellow
    New-NAVServerUser -ServerInstance $ServerInstance -UserName $Username -Password (ConvertTo-SecureString $Password -AsPlainText -Force) -ChangePasswordAtNextLogon:$false -AuthenticationKey ""
    
    # Assign permission set
    Write-Host "Assigning permission set: $PermissionSetId..." -ForegroundColor Yellow
    New-NAVServerUserPermissionSet -ServerInstance $ServerInstance -UserName $Username -PermissionSetId $PermissionSetId
    
    Write-Host "User '$Username' created successfully with permission set '$PermissionSetId'" -ForegroundColor Green
    Write-Host "Login credentials:" -ForegroundColor Cyan
    Write-Host "  Username: $Username" -ForegroundColor White
    Write-Host "  Password: $Password" -ForegroundColor White
    Write-Host "  Authentication: NavUserPassword" -ForegroundColor White
    
} catch {
    Write-Error "Failed to create user: $($_.Exception.Message)"
    Write-Host "Error details: $($_.Exception)" -ForegroundColor Red
    exit 1
}