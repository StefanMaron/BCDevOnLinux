#!/bin/bash

# Function to check if Wine prefix has required .NET components
check_wine_dotnet_components() {
    local WINEPREFIX="$1"
    local missing_components=()
    
    echo "Checking Wine prefix for required .NET components..."
    
    # Check for .NET Framework 4.8
    echo -n "Checking for .NET Framework 4.8... "
    if wine reg query "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release 2>/dev/null | grep -q "528049"; then
        echo "Found"
    else
        echo "Missing"
        missing_components+=(".NET Framework 4.8")
    fi
    
    # Check for .NET Desktop Runtime 8.0
    echo -n "Checking for .NET Desktop Runtime 8.0... "
    if [ -d "$WINEPREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App/8.0."* ]; then
        echo "Found"
    else
        echo "Missing"
        missing_components+=(".NET Desktop Runtime 8.0")
    fi
    
    # Check for ASP.NET Core Runtime 8.0
    echo -n "Checking for ASP.NET Core Runtime 8.0... "
    if [ -d "$WINEPREFIX/drive_c/Program Files/dotnet/shared/Microsoft.AspNetCore.App/8.0."* ]; then
        echo "Found"
    else
        echo "Missing"
        missing_components+=("ASP.NET Core Runtime 8.0")
    fi
    
    # Check for dotnet.exe
    echo -n "Checking for dotnet.exe... "
    if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
        echo "Found"
    else
        echo "Missing"
        missing_components+=("dotnet.exe")
    fi
    
    # Return status
    if [ ${#missing_components[@]} -eq 0 ]; then
        echo "All required .NET components are installed!"
        return 0
    else
        echo "Missing components:"
        printf '%s\n' "${missing_components[@]}"
        return 1
    fi
}

# Export the function if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f check_wine_dotnet_components
else
    # If run directly, check the current Wine prefix
    WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/bc1}"
    export WINEPREFIX
    check_wine_dotnet_components "$WINEPREFIX"
fi