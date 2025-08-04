param(
    [Parameter(Mandatory=$true)]
    [string]$ArtifactUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$DestinationPath = "/home/bcartifacts",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludePlatform,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "Starting simple BC Artifact Download..." -ForegroundColor Green
Write-Host "Artifact URL: $ArtifactUrl"
Write-Host "Destination: $DestinationPath"
Write-Host "Include Platform: $IncludePlatform"

# Parse artifact URL to get base URL and file name
$uri = [Uri]::new($ArtifactUrl)
$baseUrl = "$($uri.Scheme)://$($uri.Host)$($uri.AbsolutePath.Substring(0, $uri.AbsolutePath.LastIndexOf('/')))"
$fileName = [System.IO.Path]::GetFileNameWithoutExtension($uri.Segments[-1])

Write-Host "Base URL: $baseUrl" -ForegroundColor Cyan
Write-Host "Artifact Name: $fileName" -ForegroundColor Cyan

# Create destination directories
$appPath = Join-Path $DestinationPath "app"
$platformPath = Join-Path $DestinationPath "platform"

if ($Force -and (Test-Path $appPath)) {
    Write-Host "Removing existing app folder..." -ForegroundColor Yellow
    Remove-Item $appPath -Recurse -Force
}

if ($Force -and (Test-Path $platformPath)) {
    Write-Host "Removing existing platform folder..." -ForegroundColor Yellow
    Remove-Item $platformPath -Recurse -Force
}

New-Item -ItemType Directory -Path $appPath -Force | Out-Null

if ($IncludePlatform) {
    New-Item -ItemType Directory -Path $platformPath -Force | Out-Null
}

try {
    # Download main artifact (locale/app)
    Write-Host "Downloading main artifact..." -ForegroundColor Yellow
    $appZipUrl = $ArtifactUrl
    $appZipPath = Join-Path $appPath "app.zip"
    
    # Use wget for simple download
    $wgetArgs = @(
        "--no-verbose",
        "--output-document=$appZipPath",
        "--timeout=300",
        "--tries=3",
        "$appZipUrl"
    )
    
    Write-Host "Running: wget $($wgetArgs -join ' ')" -ForegroundColor Cyan
    $result = Start-Process -FilePath "wget" -ArgumentList $wgetArgs -Wait -PassThru -NoNewWindow
    
    if ($result.ExitCode -ne 0) {
        throw "wget failed with exit code: $($result.ExitCode)"
    }
    
    # Extract app artifact using 7z
    Write-Host "Extracting app artifact using 7z..." -ForegroundColor Yellow
    $extractResult = Start-Process -FilePath "7z" -ArgumentList @("x", $appZipPath, "-o$appPath", "-y") -Wait -PassThru -NoNewWindow
    
    if ($extractResult.ExitCode -ne 0) {
        throw "7z extraction failed with exit code: $($extractResult.ExitCode)"
    }
    
    # Clean up zip file
    Remove-Item $appZipPath -Force
    
    Write-Host "App artifact downloaded and extracted successfully!" -ForegroundColor Green
    
    # Download platform artifact if requested
    if ($IncludePlatform) {
        Write-Host "Downloading platform artifact..." -ForegroundColor Yellow
        
        # Construct platform URL
        $platformZipUrl = "$baseUrl/platform$($uri.Query)"
        $platformZipPath = Join-Path $platformPath "platform.zip"
        
        $platformWgetArgs = @(
            "--no-verbose",
            "--output-document=$platformZipPath",
            "--timeout=300",
            "--tries=3",
            "$platformZipUrl"
        )
        
        Write-Host "Running: wget $($platformWgetArgs -join ' ')" -ForegroundColor Cyan
        $platformResult = Start-Process -FilePath "wget" -ArgumentList $platformWgetArgs -Wait -PassThru -NoNewWindow
        
        if ($platformResult.ExitCode -ne 0) {
            throw "wget failed for platform with exit code: $($platformResult.ExitCode)"
        }
        
        # Extract platform artifact using 7z
        Write-Host "Extracting platform artifact using 7z..." -ForegroundColor Yellow
        $platformExtractResult = Start-Process -FilePath "7z" -ArgumentList @("x", $platformZipPath, "-o$platformPath", "-y") -Wait -PassThru -NoNewWindow
        
        if ($platformExtractResult.ExitCode -ne 0) {
            throw "7z extraction failed for platform with exit code: $($platformExtractResult.ExitCode)"
        }
        
        # Clean up zip file
        Remove-Item $platformZipPath -Force
        
        Write-Host "Platform artifact downloaded and extracted successfully!" -ForegroundColor Green
    }
    
    Write-Host "BC Artifact download completed successfully!" -ForegroundColor Green
    Write-Host "Downloaded to:" -ForegroundColor Cyan
    Write-Host "  - App: $appPath" -ForegroundColor White
    if ($IncludePlatform) {
        Write-Host "  - Platform: $platformPath" -ForegroundColor White
    }
}
catch {
    Write-Error "BC Artifact download failed: $_"
    throw
}
