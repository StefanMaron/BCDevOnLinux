# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Docker-based deployment solution for running Microsoft Dynamics 365 Business Central Server on Linux using Wine compatibility layer. The project follows the BC4Ubuntu approach, containerizing a Windows-based ERP system to run on Linux platforms.

### Key Features
- Runs BC Server on Linux via custom-built Wine with locale fixes
- Includes SQL Server 2022 Express in a separate container
- Automated .NET Framework and runtime installation
- **SOLVED**: Culture/locale issues fixed with custom Wine build
- Health checks for both containers
- Persistent data volumes for BC and SQL data
- Debugging mode with BC_AUTOSTART=false to prevent container restarts
- Build caching for faster Wine rebuilds

## Custom Wine Build Solution

The project uses a custom Wine build to fix the locale/culture issues that prevent Business Central from running on standard Wine. The `./build-wine-custom.sh` script is the main entry point that:

- Builds Wine from source with a patch that fixes the `LocaleNameToLCID` function
- Uses a multi-stage Docker build to compile Wine with all necessary dependencies
- Caches the Wine build for faster subsequent builds
- Automatically starts the BC and SQL containers once built

### Build Options

```bash
# Standard build and run
./build-wine-custom.sh

# Build only (don't start containers)
./build-wine-custom.sh --build-only

# Force rebuild without cache
./build-wine-custom.sh --no-cache

# Use external SQL server (no SQL container)
./build-wine-custom.sh --no-sql

# Show help
./build-wine-custom.sh --help
```

### What the Custom Build Fixes

The custom Wine build includes a patch (`wine-locale-display-fix.patch`) that resolves the issue where Wine's `LocaleNameToLCID("en-US")` returns 0 instead of the correct value (0x0409). This fix allows Business Central to properly initialize its culture/language support.

## Execution Flow

See [execution-flow.md](execution-flow.md) for a detailed flowchart and explanation of the container startup sequence.

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd BCDevOnLinux

# Build and start containers with custom Wine (includes locale fix)
./build-wine-custom.sh

# Check container status (both should show "healthy")
docker ps --format "table {{.Names}}\t{{.Status}}"

# View logs if needed
docker compose -f compose-wine-custom.yml logs -f bc
```

### Using External SQL Server

To use an external SQL Server instead of the containerized one:

```bash
# Set SQL server connection info
export SQL_SERVER=your-sql-server.domain.com
export SQL_SERVER_PORT=1433  # Optional, defaults to 1433
export SA_PASSWORD=YourSQLPassword

# Build and run without SQL container
./build-wine-custom.sh --no-sql

# The BC container will connect to your external SQL instance
```

## Common Development Commands

### Building and Running
```bash
# Build and run with custom Wine (recommended)
./build-wine-custom.sh

# Build only without starting
./build-wine-custom.sh --build-only

# Force rebuild from scratch
./build-wine-custom.sh --no-cache

# Stop all services
docker compose -f compose-wine-custom.yml down
```

### Container Management - Quick Access Scripts

The project includes convenient wrapper scripts for common container operations:

#### Container Access
```bash
# BC Container
./bc                    # Interactive bash shell
./bc wine --version     # Check Wine version
./bc ps aux             # List processes
./bc -i pwsh           # Interactive PowerShell

# SQL Container  
./sql                   # Interactive bash shell
./sql -i sqlcmd        # Interactive SQL command line
./sql sqlcmd -Q "SELECT name FROM sys.databases"  # Run SQL query
```

#### Logs and Status
```bash
# View logs
./logs                  # Follow logs from both containers
./logs bc              # Follow only BC logs
./logs -n sql          # Show SQL logs without following
./logs -t 50 bc        # Show last 50 lines of BC logs

# Check status
./status               # Show container health and service status
```

#### BC Service Debugging Scripts

The project includes comprehensive debugging tools for troubleshooting BC startup and SQL connection issues:

##### Wine Debug Launcher (`debug-bc-wine.sh`)
```bash
# Debug file access patterns
./debug-bc-wine.sh -c file -f CustomSettings

# Debug SQL connection issues  
./debug-bc-wine.sh --sql -t 60

# Debug configuration loading
./debug-bc-wine.sh --config -F

# Debug with multiple channels and filter
./debug-bc-wine.sh -c file,reg,odbc -f "config\|key\|sql" -F

# Full debug with no timeout
./debug-bc-wine.sh --full -t 0 -v

# Predefined channel sets:
#   --config    Config file debugging (file,reg,module)
#   --sql       SQL connection debugging (odbc,ole,reg)
#   --startup   Startup debugging (file,module,process)
#   --keys      Encryption key debugging (file,reg)
#   --full      Comprehensive debugging (file,reg,module,odbc,ole)
```

##### Log Analysis Tool (`analyze-bc-wine-log.sh`)
```bash
# Analyze most recent log with summary
./analyze-bc-wine-log.sh -s

# Analyze specific log for config issues
./analyze-bc-wine-log.sh /home/bc-debug-logs/bc-wine-debug_20240125_123456.log -c

# Search for specific pattern
./analyze-bc-wine-log.sh -p "CustomSettings"

# Analysis options:
#   -s, --summary     Show summary statistics
#   -c, --config      Analyze configuration file access
#   -k, --keys        Analyze encryption key access
#   -q, --sql         Analyze SQL/database operations
#   -f, --files       List all unique files accessed
#   -e, --errors      Show errors and warnings
#   -t, --timeline    Show timeline of operations
```

##### Quick Test Script (`bc-wine-quicktest.sh`)
```bash
# Run quick diagnostic tests
./bc-wine-quicktest.sh

# Tests:
# 1. Configuration file access patterns
# 2. Encryption key access patterns
# Provides immediate feedback on what BC is looking for
```

##### SQL Testing Scripts
```bash
# Test basic SQL connectivity from BC container
docker exec bcdevonlinux-bc-1 /opt/mssql-tools18/bin/sqlcmd -S sql -U sa -P P@ssw0rd123! -Q "SELECT 1" -C

# Test PowerShell SQL connection
docker exec bcdevonlinux-bc-1 pwsh /home/test-sql-connection.ps1

# Check active SQL sessions
./sql sqlcmd -Q "SELECT session_id, login_name, host_name, program_name FROM sys.dm_exec_sessions WHERE is_user_process = 1"
```

#### Traditional Docker Commands (still available)
```bash
# Access containers directly
docker compose -f compose-wine-custom.yml exec bc /bin/bash
docker compose -f compose-wine-custom.yml exec sql /bin/bash

# Check container health
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Wine Environment
```bash
# Access Wine prefix (inside container)
cd ~/.local/share/wineprefixes/bc1

# Run Wine configuration
winecfg

# Check Wine processes
ps aux | grep wine
```

## Architecture & Key Components

### Container Architecture
- **BC Container**: Runs Business Central via custom-built Wine with locale fixes, exposes ports 7046-7049
- **SQL Container**: SQL Server 2022 Express
- Both containers connected via `bc_network` bridge network

### Custom Wine Build Process
The project uses a multi-stage Docker build (`dockerfile-wine-custom`):
1. **Builder Stage**: Compiles Wine from source with:
   - Wine Staging patches for enhanced compatibility
   - Custom locale fix patch (`wine-locale-display-fix.patch`)
   - Full development dependencies for both 32-bit and 64-bit support
   - ccache for build acceleration (stored in `wine_cache` volume)
2. **Runtime Stage**: Minimal Ubuntu 22.04 with:
   - Custom Wine binaries from builder stage
   - Runtime dependencies only
   - Business Central server components
   - PowerShell and BC Container Helper

### Important Scripts
- `build-wine-custom.sh`: **Main entry point** - Builds custom Wine and starts containers
- `entrypoint.sh`: Main container startup orchestration
- `init-wine.sh`: Wine environment initialization
- `start-bcserver.sh`: Unified BC Server launch script with all improvements
- `install-dotnet-components.sh`: Automated .NET component installation
- `create-encryption-key.ps1`: Generates BC encryption keys
- `create-config-template.ps1`: Creates BC configuration from template
- `bc-encryption-functions.sh`: Reusable bash functions for BC password encryption
- `setup-bc-encryption.sh`: Sets up BC encryption keys and demonstrates password encryption

#### Debugging Scripts
- `debug-bc-wine.sh`: Comprehensive Wine debugging launcher with channel support
- `analyze-bc-wine-log.sh`: Log analysis tool for Wine debug output
- `bc-wine-quicktest.sh`: Quick diagnostic tests for BC configuration and key access
- `test-sql-connection.ps1`: PowerShell script to test SQL connectivity
- `test-bc-sql-encrypted.ps1`: Test BC-style encrypted SQL connections
- `test-bc-paths.ps1`: Verify BC configuration and key file paths

#### Legacy Scripts (Historical Reference)
- `legacy/culture-workarounds/`: Contains obsolete startup scripts that attempted to work around Wine locale bugs
  - See `/legacy/culture-workarounds/README.md` for historical context

### Configuration Files
- `CustomSettings.config`: BC Server configuration (database connection, service endpoints)
- `compose-wine-custom.yml`: Docker Compose service definitions for custom Wine build
- `dockerfile-wine-custom`: Multi-stage build that compiles Wine from source with locale fixes
- `wine-locale-display-fix.patch`: The patch that fixes Wine's locale handling
- `compose.yml`: Standard Docker Compose (deprecated - use custom Wine build)
- `Dockerfile`: Standard Dockerfile (deprecated - use custom Wine build)
- Environment variables:
  - `SA_PASSWORD`: SQL Server SA password (default: `P@ssw0rd123!`)
  - `BC_DATABASE_SERVER`: SQL Server hostname (default: `sql`)
  - `BC_DATABASE_NAME`: BC database name (default: `BC`)
  - `BC_AUTOSTART`: Set to `false` to prevent BC Server auto-start for debugging
  - `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT`: Must NOT be set (breaks culture support)

### Volume Mappings
- `bc_data`: BC Server data persistence
- `bc_artifacts`: BC installation files
- `wine_data`: Wine prefix data
- `wine_cache`: ccache data for faster Wine rebuilds
- `sql_data`: SQL Server databases

## Development Guidelines

### Modifying Scripts
- Shell scripts use bash and should be POSIX-compliant where possible
- PowerShell scripts run under pwsh (PowerShell Core)
- Always test Wine-related changes inside the container environment

### Working with Wine
- Wine prefix is at `~/.local/share/wineprefixes/bc1`
- .NET Framework 4.8 and .NET Desktop Runtime 6.0 are pre-installed
- Use `winetricks` for additional Windows component installation

### Debugging

#### Prevent BC Auto-start for Debugging
```bash
# Set in compose.yml or as environment variable
BC_AUTOSTART=false

# Container will stay running without starting BC Server
# Start BC manually inside container:
docker exec -it bcdevonlinux-bc-1 /bin/bash
/home/start-bcserver.sh
```

#### Wine Locale Debugging
```bash
# Enable Wine debug traces for locale issues
WINEDEBUG=+nls,+locale wine <command>

# Test specific locale function
docker exec bcdevonlinux-bc-1 pwsh -c '
    [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
'

# Check if DOTNET_SYSTEM_GLOBALIZATION_INVARIANT is set (it shouldn't be)
docker exec bcdevonlinux-bc-1 env | grep GLOBALIZATION
```

#### Common Debug Commands
```bash
# Check Wine errors
docker logs bcdevonlinux-bc-1 2>&1 | grep -E "(err:|fixme:)"

# Test culture enumeration (will fail if invariant mode is enabled)
docker exec bcdevonlinux-bc-1 pwsh -c "[System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::AllCultures).Count"

# Verify BC process is running
docker exec bcdevonlinux-bc-1 ps aux | grep Nav.Server

# Check Wine registry settings
docker exec bcdevonlinux-bc-1 wine reg query "HKEY_CURRENT_USER\Control Panel\International"
```

#### Log Locations
- Wine logs: Check container output with `docker logs`
- BC Server logs: Location varies based on configuration
- SQL connection issues: verify `BC_DATABASE_SERVER` environment variable

### Port Mappings
- 7046: OData services
- 7047: SOAP services
- 7048: Management services (disabled in BC4Ubuntu approach)
- 7049: Development services
- 1433: SQL Server (exposed from SQL container)

## Known Issues & Solutions

### Wine Culture/Locale Error (SOLVED)
- **Issue**: BC Server fails with "'en-US' is not a valid language code"
- **Root Cause**: Wine's `LocaleNameToLCID("en-US")` returns 0 instead of 0x0409
- **Detailed Analysis**: Wine's `find_lcname_entry()` function fails to find "en-US" in its binary search of the locale table, despite the locale being present in locale.nls
- **Solution**: **NOW FIXED** - The custom Wine build includes a patch that adds fallback handling in `get_locale_by_name()` function
- **Implementation**: Use `./build-wine-custom.sh` to build and run the containers with the patched Wine
- **Previous workarounds (now obsolete)**:
  - Setting `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` prevents the error but disables all culture support, breaking BC's language validation
  - Using LCID (1033) instead of culture name ("en-US") in config doesn't help
  - Setting locale environment variables (LC_ALL=C, etc.) doesn't fix the underlying Wine bug
  - Various startup script workarounds (see `legacy/culture-workarounds/` for historical context)

### Container Health Check
- BC container health is determined by Wine server process status
- Use `docker ps` to verify both containers show as "healthy"
- If BC container exits immediately, check logs for culture errors

## Known Constraints
- Management endpoints (port 7048) are intentionally disabled following BC4Ubuntu methodology
- Wine compatibility may limit certain Windows-specific BC features
- Performance overhead exists due to Wine translation layer
- BC v26 requires .NET 8.0 which has compatibility issues with Wine (use v23 for now)
- Initial build takes 20-30 minutes due to Wine compilation (subsequent builds use cache)

### Current BC Startup Issues (Under Investigation)
Despite fixing the Wine locale issue, BC Server v26 has additional challenges:
- **SQL Connection**: BC finds configuration and encryption keys but doesn't establish SQL connections
- **HTTP Endpoints**: Ports 7046-7049 return "connection reset" errors
- **Side Services**: BC fails to start reporting service under Wine
- **Root Cause**: Appears to be deeper Wine compatibility issues with BC v26's service architecture

See `SQLDEBUG.md` for detailed troubleshooting history and findings.

## Additional Resources
- `WINEPLAN.md`: Detailed technical documentation on the Wine locale bug and how to patch Wine source code
- `execution-flow.md`: Visual flowchart of the container startup sequence
- Wine debug documentation: https://wiki.winehq.org/Debug_Channels