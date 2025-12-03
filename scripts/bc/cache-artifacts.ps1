#!/usr/bin/env pwsh
# Runtime artifact caching script
# Priority: 1) Pre-mounted artifacts, 2) Cached artifacts, 3) Download fresh

param(
    [Parameter(Mandatory = $false)]
    [string]$DestinationPath = "/home/bcartifacts",

    [Parameter(Mandatory = $false)]
    [string]$PreDownloadedPath = "/home/bchost-cache"
)

# Check if verbose logging is enabled
$verboseLogging = $env:VERBOSE_LOGGING -eq "true" -or $env:VERBOSE_LOGGING -eq "1"
$curlProgressFlag = if ($verboseLogging) { "--progress-bar" } else { "--silent --show-error" }

Write-Host "Checking BC artifact cache..." -ForegroundColor Cyan

# Check if artifacts already exist in destination (already cached)
if (Test-Path "$DestinationPath/ServiceTier") {
    Write-Host "✓ Artifacts found in $DestinationPath" -ForegroundColor Green
    Write-Host "  Using cached artifacts from previous run" -ForegroundColor Green

    # Show what we're using
    $versionFile = Get-ChildItem "$DestinationPath" -Filter "*.txt" | Select-Object -First 1
    if ($versionFile) {
        Write-Host "  Version info: $($versionFile.Name)" -ForegroundColor Cyan
    }

    exit 0
}

# Check if pre-downloaded artifacts are mounted
if (Test-Path $PreDownloadedPath) {
    # Get all subdirectories in the pre-downloaded path (platform and application folders)
    $subfolders = Get-ChildItem -Path $PreDownloadedPath -Directory | Sort-Object Name -Descending

    if ($subfolders.Count -gt 0) {
        Write-Host "✓ Pre-downloaded artifacts found" -ForegroundColor Green
        Write-Host "  Found $($subfolders.Count) folder(s) in $PreDownloadedPath" -ForegroundColor Cyan
        Write-Host "  Copying to cache: $DestinationPath" -ForegroundColor Yellow

        # Copy all content from each subfolder to destination (mimics Download-Artifacts behavior)
        # Platform first (base layer), then application (overlay)
        foreach ($folder in $subfolders) {
            Write-Host "  Copying from: $($folder.Name)" -ForegroundColor Cyan
            Copy-Item -Path "$($folder.FullName)/*" -Destination $DestinationPath -Recurse -Force
        }

        # Flatten if ServiceTier is nested in a subdirectory (same as download path)
        $serviceTierPath = Get-ChildItem -Path $DestinationPath -Filter "ServiceTier" -Directory -Recurse -Depth 2 | Select-Object -First 1
        if ($serviceTierPath -and $serviceTierPath.FullName -ne "$DestinationPath/ServiceTier") {
            Write-Host "  Flattening nested artifact structure..." -ForegroundColor Yellow
            $parentDir = $serviceTierPath.Parent.FullName
            Get-ChildItem -Path $parentDir | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $DestinationPath -Recurse -Force
            }
            # Clean up the now-redundant parent directory
            Remove-Item -Path $parentDir -Recurse -Force
            Write-Host "  Structure flattened" -ForegroundColor Green
        }

        Write-Host "✓ Pre-downloaded artifacts cached" -ForegroundColor Green

        # Display contents of destination path
        Write-Host "`nCached artifact contents:" -ForegroundColor Cyan
        Get-ChildItem -Path $DestinationPath | ForEach-Object {
            if ($_.PSIsContainer) {
                Write-Host "  📁 $($_.Name)" -ForegroundColor Yellow
            }
            else {
                Write-Host "  📄 $($_.Name)" -ForegroundColor White
            }
        }
        exit 0
    }
}

Write-Host "No cached artifacts found, downloading..." -ForegroundColor Yellow

# Get artifact URL based on environment variables
Import-Module BcContainerHelper -DisableNameChecking

$artifactUrl = $env:BC_ARTIFACT_URL

if (-not $artifactUrl) {
    $version = $env:BC_VERSION
    $country = $env:BC_COUNTRY
    $type = $env:BC_TYPE
    if (-not $version) { $version = "26" }
    if (-not $country) { $country = "w1" }
    if (-not $type) { $type = "Sandbox" }

    Write-Host "Resolving artifact URL for:" -ForegroundColor Cyan
    Write-Host "  Version: $version" -ForegroundColor White
    Write-Host "  Country: $country" -ForegroundColor White
    Write-Host "  Type: $type" -ForegroundColor White
    try {

        $artifactUrl = Get-BCartifactUrl -version $version -country $country -type $type
    }
    catch {
        Write-Error "Failed to resolve BC artifact URL: $_"
        exit 1
    }
}
try {
    Write-Host "  Application URL: $artifactUrl" -ForegroundColor White

    # Construct platform URL from application URL
    $appUri = [Uri]$artifactUrl
    $platformUrl = "$($appUri.AbsolutePath.Substring(0,$appUri.AbsolutePath.LastIndexOf('/')))/platform".TrimStart('/')
    if ($platformUrl -notlike 'https://*') {
        $platformUrl = "https://$($appUri.Host.TrimEnd('/'))/$platformUrl$($appUri.Query)"
    }
    Write-Host "  Platform URL: $platformUrl" -ForegroundColor White

    Write-Host "Downloading artifacts directly (this may take several minutes)..." -ForegroundColor Yellow

    # Download platform artifact (base layer) - using curl for maximum speed on Linux
    Write-Host "  Downloading platform artifact..." -ForegroundColor Cyan
    $platformZip = Join-Path ([System.IO.Path]::GetTempPath()) "platform-$([Guid]::NewGuid().ToString()).zip"
    Invoke-Expression "curl -L -o `$platformZip `"$platformUrl`" --max-time 600 $curlProgressFlag"
    Write-Host "  Extracting platform to $DestinationPath..." -ForegroundColor Cyan
    7z x $platformZip -o"$DestinationPath" -y | Out-Null
    Remove-Item $platformZip -Force

    # Download application artifact (overlay)
    Write-Host "  Downloading application artifact..." -ForegroundColor Cyan
    $appZip = Join-Path ([System.IO.Path]::GetTempPath()) "app-$([Guid]::NewGuid().ToString()).zip"
    Invoke-Expression "curl -L -o `$appZip `"$artifactUrl`" --max-time 600 $curlProgressFlag"
    Write-Host "  Extracting application to $DestinationPath..." -ForegroundColor Cyan
    7z x $appZip -o"$DestinationPath" -aoa | Out-Null
    Remove-Item $appZip -Force

    # Flatten if ServiceTier is nested in a subdirectory
    $serviceTierPath = Get-ChildItem -Path $DestinationPath -Filter "ServiceTier" -Directory -Recurse -Depth 2 | Select-Object -First 1
    if ($serviceTierPath -and $serviceTierPath.FullName -ne "$DestinationPath/ServiceTier") {
        Write-Host "  Flattening nested artifact structure..." -ForegroundColor Yellow
        $parentDir = $serviceTierPath.Parent.FullName
        Get-ChildItem -Path $parentDir | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $DestinationPath -Recurse -Force
        }
        # Clean up the now-redundant parent directory
        Remove-Item -Path $parentDir -Recurse -Force
        Write-Host "  Structure flattened" -ForegroundColor Green
    }

    Write-Host "✓ Artifacts cached successfully" -ForegroundColor Green
    Write-Host "  Location: $DestinationPath" -ForegroundColor Cyan

}
catch {
    Write-Error "Failed to download BC artifacts: $_"
    exit 1
}
