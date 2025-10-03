#!/usr/bin/env pwsh
# Runtime artifact caching script
# Priority: 1) Pre-mounted artifacts, 2) Cached artifacts, 3) Download fresh

param(
    [Parameter(Mandatory=$false)]
    [string]$DestinationPath = "/home/bcartifacts",

    [Parameter(Mandatory=$false)]
    [string]$PreDownloadedPath = "/home/bchost-cache"
)

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
    # Find ServiceTier in the pre-downloaded path (handles nested structures)
    $serviceTierPath = Get-ChildItem -Path $PreDownloadedPath -Filter "ServiceTier" -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($serviceTierPath) {
        Write-Host "✓ Pre-downloaded artifacts found" -ForegroundColor Green
        $sourcePath = $serviceTierPath.Parent.FullName
        Write-Host "  Source: $sourcePath" -ForegroundColor Cyan
        Write-Host "  Copying to cache: $DestinationPath" -ForegroundColor Yellow

        Copy-Item -Path "$sourcePath/*" -Destination $DestinationPath -Recurse -Force

        Write-Host "✓ Pre-downloaded artifacts cached" -ForegroundColor Green
        exit 0
    }
}

Write-Host "No cached artifacts found, downloading..." -ForegroundColor Yellow

# Get artifact URL based on environment variables
Import-Module BcContainerHelper

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
    Write-Host "  URL: $artifactUrl" -ForegroundColor White

    Write-Host "Downloading artifacts (this may take several minutes)..." -ForegroundColor Yellow
    $artifactPaths = Download-Artifacts $artifactUrl -includePlatform

    Write-Host "Copying artifacts to cache..." -ForegroundColor Yellow

    # Copy platform first (base layer)
    Write-Host "  Platform: $($artifactPaths[1]) → $DestinationPath" -ForegroundColor Cyan
    Copy-Item -Path "$($artifactPaths[1])/*" -Destination $DestinationPath -Recurse -Force

    # Copy application (overlays on platform)
    Write-Host "  Application: $($artifactPaths[0]) → $DestinationPath" -ForegroundColor Cyan
    Copy-Item -Path "$($artifactPaths[0])/*" -Destination $DestinationPath -Recurse -Force

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

} catch {
    Write-Error "Failed to download BC artifacts: $_"
    exit 1
}
