#!/bin/bash
# Debug BC configuration file

# Source Wine environment
if [ -f /home/scripts/wine/wine-env.sh ]; then
    source /home/scripts/wine/wine-env.sh >/dev/null 2>&1
fi

echo "=== BC Configuration Debug ==="
echo ""

# Dynamically detect BC version
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260")
echo "Detected BC version: $BC_VERSION"
echo ""

# Check all possible config locations
echo "1. Checking Wine prefix location:"
WINE_CONFIG="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VERSION/Service/CustomSettings.config"
if [ -f "$WINE_CONFIG" ]; then
    echo "   Found at: $WINE_CONFIG"
    echo "   Size: $(stat -c%s "$WINE_CONFIG") bytes"
    echo "   First few SQL-related lines:"
    grep -E "(DatabaseServer|DatabaseInstance|DatabaseName|Password)" "$WINE_CONFIG" | head -5
else
    echo "   NOT FOUND"
fi

echo ""
echo "2. Checking /home/bcserver/:"
if [ -f "/home/bcserver/CustomSettings.config" ]; then
    echo "   Found at: /home/bcserver/CustomSettings.config"
    echo "   Size: $(stat -c%s "/home/bcserver/CustomSettings.config") bytes"
    echo "   First few SQL-related lines:"
    grep -E "(DatabaseServer|DatabaseInstance|DatabaseName|Password)" "/home/bcserver/CustomSettings.config" | head -5
else
    echo "   NOT FOUND"
fi

echo ""
echo "3. Checking /home/:"
if [ -f "/home/CustomSettings.config" ]; then
    echo "   Found at: /home/CustomSettings.config"
    echo "   Size: $(stat -c%s "/home/CustomSettings.config") bytes"
    echo "   First few SQL-related lines:"
    grep -E "(DatabaseServer|DatabaseInstance|DatabaseName|Password)" "/home/CustomSettings.config" | head -5
else
    echo "   NOT FOUND"
fi

echo ""
echo "4. Comparing file sizes (if multiple exist):"
ls -la /home/CustomSettings.config 2>/dev/null
ls -la /home/bcserver/CustomSettings.config 2>/dev/null
ls -la "$WINE_CONFIG" 2>/dev/null

echo ""
echo "5. Check if start-bcserver.sh copied the config:"
if [ -f "/home/scripts/docker/start-bcserver.sh" ]; then
    echo "   Looking for copy commands in start-bcserver.sh:"
    grep -n "CustomSettings.config" /home/scripts/docker/start-bcserver.sh | grep -E "(cp|copy)"
fi