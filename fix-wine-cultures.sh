#!/bin/bash

set -e

echo "Applying Wine culture fixes to prevent duplicates..."

# Set Wine environment
export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64

# Ensure Wine prefix exists
if [ ! -d "$WINEPREFIX" ]; then
    echo "Wine prefix not found at $WINEPREFIX"
    exit 1
fi

# Set minimal locale in Wine registry to reduce culture enumeration
echo "Configuring Wine registry for minimal culture support..."

# Set the system locale to en-US only
wine reg add "HKEY_CURRENT_USER\Control Panel\International" /v Locale /t REG_SZ /d 00000409 /f
wine reg add "HKEY_CURRENT_USER\Control Panel\International" /v LocaleName /t REG_SZ /d en-US /f
wine reg add "HKEY_CURRENT_USER\Control Panel\International" /v sLanguage /t REG_SZ /d ENU /f
wine reg add "HKEY_CURRENT_USER\Control Panel\International" /v sCountry /t REG_SZ /d "United States" /f

# Set system locale
wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\Language" /v Default /t REG_SZ /d 0409 /f
wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\Language" /v InstallLanguage /t REG_SZ /d 0409 /f

# Limit available locales
wine reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\Locale" /v "(Default)" /t REG_SZ /d 00000409 /f
wine reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\Locale" /v 00000409 /t REG_SZ /d en-US /f

echo "Wine culture fixes applied."