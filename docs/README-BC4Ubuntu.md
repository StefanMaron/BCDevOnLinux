# BC Development on Linux - BC4Ubuntu Approach

This project enables running Microsoft Business Central Server on Linux using Docker and Wine, following the proven methodology from the [BC4Ubuntu project](https://github.com/SShadowS/BC4Ubuntu).

## Key Changes from Original Approach

This implementation now follows the BC4Ubuntu methodology for better Wine compatibility:

### Wine Configuration
- Uses `wine-staging` for better .NET compatibility
- Creates Wine prefix in `~/.local/share/wineprefixes/bc1` (BC4Ubuntu standard)
- Installs .NET Framework 4.8 followed by .NET Desktop Runtime 6.0
- Uses winetricks for reliable component installation

### Installation Process
1. Base Ubuntu 22.04 with wine-staging
2. Install winetricks from official repository
3. Create 64-bit Wine prefix
4. Install .NET Framework 4.8 via winetricks
5. Install .NET Desktop Runtime 6.0 via winetricks
6. Configure Wine registry for BC Server compatibility

## Quick Start

### Build the Container
```bash
docker build -t bc-linux .
```

### Run with SQL Server
```bash
docker-compose up
```

### Manual Wine Setup (if needed)
```bash
# Enter the running container
docker exec -it bc-linux bash

# Run interactive Wine setup
./setup-wine-interactive.sh
```

## Wine Prefix Structure

Following BC4Ubuntu approach, the Wine prefix is located at:
- **Location**: `$HOME/.local/share/wineprefixes/bc1`
- **Architecture**: 64-bit (win64)
- **Components**: .NET 4.8, .NET Desktop 6.0

## Configuration Files

- **Wine Config**: Stored in Wine prefix
- **BC Config**: `/home/bcserver/CustomSettings.config`
- **Encryption Key**: `/home/bcserver/Keys/bc.key`

## Troubleshooting

### Wine Issues
```bash
# Check Wine prefix
ls -la ~/.local/share/wineprefixes/bc1/

# Test Wine
WINEPREFIX=~/.local/share/wineprefixes/bc1 wine --version

# Reinstall Wine components
winetricks prefix=bc1 -q dotnet48
winetricks prefix=bc1 -q dotnetdesktop6
```

### BC Server Issues
```bash
# Check BC artifacts
find /home/bcartifacts -name "*.exe" | head -10

# Verify configuration
cat /home/bcserver/CustomSettings.config

# Check encryption key
ls -la /home/bcserver/Keys/
```

## Based on BC4Ubuntu

This project adapts the successful approach from [SShadowS/BC4Ubuntu](https://github.com/SShadowS/BC4Ubuntu), which successfully runs Business Central NST on Ubuntu via Wine.

### Key BC4Ubuntu Learnings Applied:
1. Use wine-staging for better compatibility
2. Install .NET components in specific order
3. Proper Wine prefix management
4. Disable problematic services initially
5. Use winetricks for reliable installations

## Current Status

- ✅ Wine-staging installation
- ✅ Wine prefix creation
- ✅ Basic .NET Framework installation
- 🔄 BC Server execution (in progress)
- ❌ Management endpoints (disabled per BC4Ubuntu)

## Next Steps

1. Complete .NET component installation
2. Test BC Server startup
3. Configure endpoints following BC4Ubuntu guidance
4. Add PowerShell 5.1 installation
5. Test with actual BC development scenarios

## Contributing

This is a work in progress. The BC4Ubuntu project has proven that BC Server can run on Linux via Wine. This Docker implementation aims to make that setup more accessible and reproducible.
