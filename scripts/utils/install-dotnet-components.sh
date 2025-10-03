#!/bin/bash

set -e

echo "Installing .NET components for BC Server v26..."

# Status file for progress tracking
STATUS_FILE="/home/bc-init-status.txt"

# Set Wine environment variables
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Ensure Wine prefix exists
if [ ! -d "$WINEPREFIX" ]; then
    echo "ERROR: Wine prefix not found. Run init-wine.sh first."
    exit 1
fi

# # Check if .NET 8 is already installed
# if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
#     echo ".NET 8 runtime already installed, checking version..."
#     wine "C:\\Program Files\\dotnet\\dotnet.exe" --version 2>/dev/null | grep -v fixme || echo "Unable to determine version"
# else
#     echo "Installing .NET 8.0 Desktop Runtime..."
#     echo "STATUS: Installing .NET 8.0 Desktop Runtime..." >> "$STATUS_FILE"
#     cd /tmp
    
#     # Download .NET 8.0.8 Desktop Runtime using curl with headers
#     echo "Downloading .NET 8.0.8 Desktop Runtime..."
#     echo "STATUS: Downloading .NET 8.0.8 Desktop Runtime..." >> "$STATUS_FILE"
#     curl -L -H 'User-Agent: Mozilla/5.0' -o dotnet8-desktop.exe \
#         'https://dotnetcli.azureedge.net/dotnet/WindowsDesktop/8.0.8/windowsdesktop-runtime-8.0.8-win-x64.exe'
    
#     if [ -f "dotnet8-desktop.exe" ] && [ -s "dotnet8-desktop.exe" ]; then
#         echo "Installing .NET 8 Desktop Runtime in Wine..."
#         echo "STATUS: Running .NET 8 Desktop Runtime installer..." >> "$STATUS_FILE"
#         wine dotnet8-desktop.exe /quiet /install /norestart
#         rm -f dotnet8-desktop.exe
#         echo ".NET 8 Desktop Runtime installed"
#         echo "STATUS: .NET 8 Desktop Runtime installed successfully" >> "$STATUS_FILE"
#     else
#         echo "ERROR: Failed to download .NET 8 Desktop Runtime"
#         echo "STATUS: ERROR - Failed to download .NET 8 Desktop Runtime" >> "$STATUS_FILE"
#         exit 1
#     fi
# fi

# # Install ASP.NET Core 8 Hosting Bundle
# echo "Installing ASP.NET Core 8.0 Hosting Bundle..."
# echo "STATUS: Installing ASP.NET Core 8.0 Hosting Bundle..." >> "$STATUS_FILE"
# cd /tmp

# # Download ASP.NET Core 8.0.8 hosting bundle
# echo "Downloading ASP.NET Core 8.0.8 hosting bundle..."
# echo "STATUS: Downloading ASP.NET Core 8.0.8 hosting bundle..." >> "$STATUS_FILE"
# curl -L -H 'User-Agent: Mozilla/5.0' -o aspnetcore8-hosting.exe \
#     'https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/8.0.8/dotnet-hosting-8.0.8-win.exe'

# if [ -f "aspnetcore8-hosting.exe" ] && [ -s "aspnetcore8-hosting.exe" ]; then
#     echo "Installing ASP.NET Core hosting bundle in Wine..."
#     echo "STATUS: Running ASP.NET Core hosting bundle installer..." >> "$STATUS_FILE"
#     wine aspnetcore8-hosting.exe /quiet /install /norestart
#     rm -f aspnetcore8-hosting.exe
#     echo "ASP.NET Core 8 hosting bundle installed"
#     echo "STATUS: ASP.NET Core 8 hosting bundle installed successfully" >> "$STATUS_FILE"
# else
#     echo "ERROR: Failed to download ASP.NET Core hosting bundle"
#     echo "STATUS: ERROR - Failed to download ASP.NET Core hosting bundle" >> "$STATUS_FILE"
#     exit 1
# fi

# Verify installation
echo "Verifying .NET installation..."
if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
    echo "✓ .NET 8 runtime installed successfully"
    ls -la "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe"
else
    echo "✗ .NET 8 runtime installation failed"
    exit 1
fi

echo ".NET components installation completed"
