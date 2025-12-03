#!/bin/bash
# Wine environment variables for BC Server

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"

# Also set DOTNET_ROOT for BC Server v26
export DOTNET_ROOT="C:\\Program Files\\dotnet"

# Helpful aliases
# Dynamic cdbc alias that detects BC version
alias cdbc='BC_VER=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null || echo "260"); cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/$BC_VER/Service"'
alias bclog='tail -f /home/bc-init-status.txt 2>/dev/null || echo "No initialization log found"'
alias bcstatus='/home/tests/check-bc-status.sh'

# Only show output if running interactively
if [ -t 1 ]; then
    echo "Wine environment configured:"
    echo "  WINEPREFIX: $WINEPREFIX"
    echo "  WINEARCH: $WINEARCH"
fi