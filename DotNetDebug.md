# Business Central v26 .NET Installation Debug Log

This document captures all steps, attempts, and results from installing the required .NET components for Business Central v26 in Wine.

## Overview

Business Central v26 has a unique dual .NET architecture:
- **Main BC Server**: Requires .NET Framework 4.8 (traditional Windows .NET)
- **Reporting Service**: Requires .NET 8.0 Runtime (modern cross-platform .NET)

Both must be installed in Wine for BC to function properly.

## Initial Discovery

### Problem Identification
When attempting to start BC Server v26, encountered these errors:

```
Wine could not find the program L"dotnet"
ERROR: Failed to start reporting service
Error: BC Server crashed with exit code 1
```

### Root Cause Analysis
1. Checked BC artifacts structure and found `/SideServices/Microsoft.BusinessCentral.Reporting.Service.exe`
2. This is a .NET Core/5+ executable requiring the `dotnet` runtime
3. The main BC Server (`Microsoft.Dynamics.Nav.Server.exe`) is a .NET Framework application

## Installation Attempts

### Attempt 1: Install .NET Framework 4.8 Only

**Command:**
```bash
winetricks dotnet48
```

**Result:**
- Successfully installed after ~10-15 minutes
- Main BC Server could start
- But reporting service failed with "dotnet" not found

### Attempt 2: Install .NET 8.0 via Winetricks

**Command:**
```bash
winetricks dotnetdesktop8
```

**Result:**
- Downloads windowsdesktop-runtime-8.0.12-win-x86.exe and windowsdesktop-runtime-8.0.12-win-x64.exe
- Installation appears to start but hangs indefinitely
- Process gets stuck, requiring manual termination

### Attempt 3: Manual Installation of .NET 8.0 Runtime

**Commands:**
```bash
cd /tmp
wget https://download.visualstudio.microsoft.com/download/pr/[...]/dotnet-runtime-8.0.18-win-x64.exe
wine dotnet-runtime-8.0.18-win-x64.exe /quiet /install
```

**Result:**
- Download fails due to URL construction issues
- Microsoft's CDN doesn't serve files to simple wget requests

### Attempt 4: Direct Binary Extraction

**Commands:**
```bash
# Download using Windows machine or browser
# Extract using 7z
7z x windowsdesktop-runtime-8.0.18-win-x64.exe -o/tmp/dotnet8
# Copy to Wine prefix
cp -r /tmp/dotnet8/* "$WINEPREFIX/drive_c/Program Files/dotnet/"
```

**Result:**
- Files copied but Wine couldn't locate dotnet.exe
- Path registration issues

## Working Solution

### Key Discovery
BC v26 is looking for `dotnet.exe` at `C:\Program Files\dotnet\dotnet.exe` specifically. The installation must:
1. Place files in the correct Wine prefix location
2. Register the installation properly in Wine's registry
3. Use the correct installer with `/quiet` flag

### Prerequisites
- Wine prefix initialized with .NET Framework 4.8
- 64-bit Wine prefix (WINEARCH=win64)

### Installation Steps

**1. Install .NET Framework 4.8 (if not already installed):**
```bash
WINEPREFIX="$HOME/.local/share/wineprefixes/bc1" winetricks -q dotnet48
```

**2. Download .NET 8.0 Desktop Runtime:**
```bash
cd /tmp
# Official download from Microsoft
wget -O windowsdesktop-runtime-8.0.18-win-x64.exe \
  "https://download.visualstudio.microsoft.com/download/pr/[full-url]/windowsdesktop-runtime-8.0.18-win-x64.exe"
```

**3. Install in Wine:**
```bash
WINEPREFIX="$HOME/.local/share/wineprefixes/bc1" \
  wine windowsdesktop-runtime-8.0.18-win-x64.exe /quiet /install /norestart
```

**4. Install ASP.NET Core Hosting Bundle:**
```bash
wget -O dotnet-hosting-8.0.18-win.exe \
  "https://download.visualstudio.microsoft.com/download/pr/[full-url]/dotnet-hosting-8.0.18-win.exe"
  
WINEPREFIX="$HOME/.local/share/wineprefixes/bc1" \
  wine dotnet-hosting-8.0.18-win.exe /quiet /install /norestart
```

### Registry Configuration

**In Wine Registry:**
```bash
wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" \
  /v DOTNET_ROOT /t REG_SZ /d "C:\\Program Files\\dotnet" /f

wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" \
  /v Path /t REG_EXPAND_SZ \
  /d "%SystemRoot%\\system32;%SystemRoot%;C:\\Program Files\\dotnet" /f
```

## Working Installation Process (July 27, 2025)

### Issue: BC v26 requires .NET 8.0.18 runtime

When starting BC Server v26, it failed with:
```
wine: failed to open "C:\\Program Files\\dotnet\\dotnet.exe"
You must install .NET to run this application.
App host version: 8.0.18
.NET location: Not found
```

### Solution: Manual installation of .NET 8 Desktop Runtime

Due to Microsoft CDN blocking direct wget downloads, we need to use curl with proper headers:

#### Step 1: Download .NET 8 Desktop Runtime
```bash
cd /tmp
curl -L -H 'User-Agent: Mozilla/5.0' -o dotnet8-desktop.exe \
  'https://dotnetcli.azureedge.net/dotnet/WindowsDesktop/8.0.8/windowsdesktop-runtime-8.0.8-win-x64.exe'
```

#### Step 2: Install in Wine
```bash
export WINEPREFIX=/root/.local/share/wineprefixes/bc1
export WINEARCH=win64
wine dotnet8-desktop.exe /quiet /install /norestart
```

#### Step 3: Install ASP.NET Core 8 Hosting Bundle
```bash
curl -L -H 'User-Agent: Mozilla/5.0' -o aspnetcore8-hosting.exe \
  'https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/8.0.8/dotnet-hosting-8.0.8-win.exe'
wine aspnetcore8-hosting.exe /quiet /install /norestart
```

#### Step 4: Verify Installation
```bash
# Check if dotnet.exe exists
ls -la '/root/.local/share/wineprefixes/bc1/drive_c/Program Files/dotnet/dotnet.exe'
# Should show: -rwxr-xr-x 1 root root 146608 Jul 16  2024 dotnet.exe
```

### Result
After installation, BC Server v26 starts successfully with both:
- Main BC Server process: `Microsoft.Dynamics.Nav.Server.exe`
- Reporting Service: `dotnet.exe Microsoft.BusinessCentral.Reporting.Service.exe`

## Final Working Configuration

### Updated init-wine.sh

The script now includes both .NET installations:

```bash
# Install .NET Framework 4.8 first (BC Server v26 needs this for main server)
echo "Installing .NET Framework 4.8..."
winetricks prefix=bc1 -q dotnet48

# Wait for .NET Framework installation to settle
sleep 5

# Install .NET Desktop Runtime 8.0 directly (BC Server v26 needs this)
echo "Installing .NET Desktop Runtime 8.0..."
cd /tmp
wget -q "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.18/windowsdesktop-runtime-8.0.18-win-x64.exe"
wine windowsdesktop-runtime-8.0.18-win-x64.exe /quiet /install /norestart
rm -f windowsdesktop-runtime-8.0.18-win-x64.exe

# Install ASP.NET Core 8.0 hosting bundle
echo "Installing ASP.NET Core 8.0 hosting bundle..."
wget -O "dotnet-hosting-8.0.18-win.exe" \
  "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.18/dotnet-hosting-8.0.18-win.exe"
wine dotnet-hosting-8.0.18-win.exe /quiet /install /norestart
rm -f dotnet-hosting-8.0.18-win.exe
```

### Updated start-bcserver.sh

The script now properly starts the reporting service:

```bash
# Start the reporting service with .NET 8.0
if [ -f "$BC_SERVICE_DIR/SideServices/Microsoft.BusinessCentral.Reporting.Service.exe" ]; then
    echo "Starting Reporting Service..."
    cd "$BC_SERVICE_DIR/SideServices"
    wine "C:\\Program Files\\dotnet\\dotnet.exe" Microsoft.BusinessCentral.Reporting.Service.exe &
    REPORTING_PID=$!
    echo "Reporting Service started with PID: $REPORTING_PID"
fi

# Start main BC Server
cd "$BC_SERVICE_DIR"
wine "$BC_SERVER_EXE" /console
```

## Key Learnings

1. **BC v26 Architecture Change**: Unlike previous versions, BC v26 uses .NET 8.0 for certain components (reporting service)
2. **Dual Runtime Requirement**: Both .NET Framework 4.8 and .NET 8.0 Runtime must be installed
3. **Installation Order**: .NET Framework 4.8 should be installed first, then .NET 8.0
4. **Wine Path Resolution**: dotnet.exe must be at exactly `C:\Program Files\dotnet\dotnet.exe`
5. **Silent Installation**: Use `/quiet /install /norestart` flags for unattended installation

## Verification Steps

### 1. Check .NET Framework 4.8
```bash
# Inside container
wine reg query "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release
# Should show: Release    REG_DWORD    0x80ff8 (528040 = .NET 4.8)
```

### 2. Check .NET 8.0 Runtime
```bash
# Inside container
wine "C:\\Program Files\\dotnet\\dotnet.exe" --list-runtimes
# Should show:
# Microsoft.AspNetCore.App 8.0.18
# Microsoft.NETCore.App 8.0.18
# Microsoft.WindowsDesktop.App 8.0.18
```

### 3. Verify Wine Prefix Structure
```bash
# Check dotnet installation
ls -la "$WINEPREFIX/drive_c/Program Files/dotnet/"
# Should contain: dotnet.exe, shared/, host/, etc.

# Check .NET Framework
ls -la "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/"
# Should contain many .dll files
```

## Troubleshooting

### Common Issues

1. **"dotnet.exe not found" error**
   - Verify installation path: `ls -la "$WINEPREFIX/drive_c/Program Files/dotnet/"`
   - Check Wine path mapping: `wine cmd /c echo %PATH%`

2. **Reporting service fails to start**
   - Ensure .NET 8.0 Desktop Runtime is installed (not just core runtime)
   - Check for Microsoft.BusinessCentral.Reporting.Service.exe in SideServices folder

3. **Installation hangs**
   - Don't use winetricks for .NET 8.0 (it has issues)
   - Use direct installer with `/quiet` flag
   - If GUI appears, installation will likely hang

4. **Download failures**
   - Microsoft CDN blocks simple wget requests
   - Use curl with User-Agent header
   - Alternative: Download on Windows and transfer to container

## References

- [Microsoft .NET Download Page](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Wine Application Database - .NET](https://appdb.winehq.org/objectManager.php?sClass=application&iId=17886)
- [BC v26 System Requirements](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/deployment/system-requirements)