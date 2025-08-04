#!/bin/bash
# Wine environment variables for BC Server

export WINEPREFIX="$HOME/.local/share/wineprefixes/bc1"
export WINEARCH=win64
export DISPLAY=":0"
export WINE_SKIP_GECKO_INSTALLATION=1
export WINE_SKIP_MONO_INSTALLATION=1

# Also set DOTNET_ROOT for BC Server v26
export DOTNET_ROOT="C:\\Program Files\\dotnet"

# Add Wine to PATH if not already there
if ! command -v wine &> /dev/null; then
    export PATH="/opt/wine-custom/bin:$PATH"
fi

# Helpful aliases
alias cdbc='cd "$WINEPREFIX/drive_c/Program Files/Microsoft Dynamics NAV/260/Service"'
alias bclog='tail -f /home/bc-init-status.txt 2>/dev/null || echo "No initialization log found"'
alias bcstatus='/home/check-bc-status.sh'

# Only show output if running interactively
if [ -t 1 ]; then
    echo "Wine environment configured:"
    echo "  WINEPREFIX: $WINEPREFIX"
    echo "  WINEARCH: $WINEARCH"
fi