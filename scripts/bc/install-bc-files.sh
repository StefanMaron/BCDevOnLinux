#!/bin/bash
set -e

echo "Installing BC Server by copying files (MSI alternative)..."

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
WINE_BC_DIR="$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service"
BC_ARTIFACTS="/home/bcartifacts/ServiceTier/program files/Microsoft Dynamics NAV/260/Service"

# Check if already installed with all required files
if [ -f "$WINE_BC_DIR/Microsoft.Dynamics.Nav.Server.exe" ] && \
   [ -f "$WINE_BC_DIR/Microsoft.Dynamics.Nav.Server.deps.json" ] && \
   [ -f "$WINE_BC_DIR/Microsoft.Dynamics.Nav.Server.runtimeconfig.json" ]; then
    echo "BC Server already installed with all required files"
    exit 0
fi

echo "Copying entire BC Service directory from artifacts..."
# Create parent directory structure
mkdir -p "$(dirname "$WINE_BC_DIR")"
# Remove existing directory and copy everything 1:1
rm -rf "$WINE_BC_DIR"
cp -r "$BC_ARTIFACTS" "$(dirname "$WINE_BC_DIR")"

# Verify all files were copied
SOURCE_FILE_COUNT=$(find "$BC_ARTIFACTS" -maxdepth 1 -type f -name "*.*" 2>/dev/null | wc -l)
DEST_FILE_COUNT=$(find "$WINE_BC_DIR" -maxdepth 1 -type f -name "*.*" 2>/dev/null | wc -l)

if [ "$SOURCE_FILE_COUNT" -ne "$DEST_FILE_COUNT" ]; then
    echo "WARNING: File count mismatch! Source: $SOURCE_FILE_COUNT, Destination: $DEST_FILE_COUNT"
    echo "Attempting to copy missing files..."
    # Copy any missing files
    cd "$BC_ARTIFACTS"
    for file in *.*; do
        if [ ! -f "$WINE_BC_DIR/$file" ]; then
            echo "Copying missing file: $file"
            cp "$file" "$WINE_BC_DIR/"
        fi
    done
    cd - > /dev/null
fi

# Count total DLLs
DLL_COUNT=$(find "$WINE_BC_DIR" -name "*.dll" 2>/dev/null | wc -l)
echo "Installed $DLL_COUNT DLL files in Service directory"

# Verify critical files exist
CRITICAL_FILES=(
    "Microsoft.Dynamics.Nav.Server.exe"
    "Microsoft.Dynamics.Nav.Server.deps.json"
    "Microsoft.Dynamics.Nav.Server.runtimeconfig.json"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$WINE_BC_DIR/$file" ]; then
        echo "ERROR: Critical file missing: $file"
        exit 1
    fi
done
echo "All critical files verified"

# Copy CustomSettings.config
if [ -f "/home/CustomSettings.config" ]; then
    cp -f "/home/CustomSettings.config" "$WINE_BC_DIR/CustomSettings.config"
    echo "Custom configuration applied"
fi

# Install encryption keys
KEY_DIR="$WINEPREFIX/drive_c/ProgramData/Microsoft/Microsoft Dynamics NAV/260/Server/Keys"
mkdir -p "$KEY_DIR"
if [ -f "/home/config/secret.key" ]; then
    cp "/home/config/secret.key" "$KEY_DIR/bc.key"
    cp "/home/config/secret.key" "$KEY_DIR/BC.key"
    cp "/home/config/secret.key" "$KEY_DIR/BusinessCentral260.key"
    cp "/home/config/secret.key" "$KEY_DIR/DynamicsNAV90.key"
    echo "Encryption keys installed"
fi

echo "BC Server file installation completed"