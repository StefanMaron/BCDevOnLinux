#!/bin/bash
# Wine debugging script for BC Server
# Allows easy debugging with different Wine channels and log management

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
LOG_DIR="/home/bc-debug-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_CHANNELS="file,reg"
TIMEOUT_SECONDS=30
FILTER_PATTERN=""
FOLLOW_LOG=false
VERBOSE=false

# Dynamically detect BC version
BC_VERSION=$(find "/home/bcartifacts/platform/ServiceTier/program files/Microsoft Dynamics NAV" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1 | xargs basename 2>/dev/null || echo "260")

# BC Server paths
BC_SERVER_PATH="/home/bcartifacts/platform/ServiceTier/program files/Microsoft Dynamics NAV/$BC_VERSION/Service"
BC_SERVER_EXE="Microsoft.Dynamics.Nav.Server.exe"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Wine debugging launcher for BC Server with comprehensive logging

OPTIONS:
    -c, --channels CHANNELS    Wine debug channels (comma-separated)
                              Default: "$DEFAULT_CHANNELS"
                              Available channels:
                                file      - File operations
                                reg       - Registry operations
                                module    - DLL loading
                                odbc      - ODBC operations
                                ole       - COM/OLE operations
                                seh       - Exception handling
                                relay     - All API calls (VERY verbose)
                                heap      - Heap operations
                                ntdll     - NT DLL operations
                                kernel    - Kernel operations
                                server    - Wine server operations
                                sync      - Synchronization
                                thread    - Threading operations
                                process   - Process operations
                                dll       - DLL operations
                                environ   - Environment variables
                                +all      - Enable all channels (warning: huge logs)

    -t, --timeout SECONDS     Timeout in seconds (default: $TIMEOUT_SECONDS)
                              Use 0 for no timeout

    -f, --filter PATTERN      Filter output for specific pattern
                              Examples: "CustomSettings", "\.key", "sql"

    -l, --log-dir DIR         Log directory (default: $LOG_DIR)

    -F, --follow              Follow log output in real-time

    -v, --verbose             Show verbose output

    -h, --help                Show this help message

PREDEFINED CHANNEL SETS:
    --config                  Channels for config file debugging (file,reg,module)
    --sql                     Channels for SQL connection debugging (odbc,ole,reg)
    --startup                 Channels for startup debugging (file,module,process)
    --keys                    Channels for encryption key debugging (file,reg)
    --full                    Comprehensive debugging (file,reg,module,odbc,ole)

EXAMPLES:
    # Debug file access
    $0 -c file -f CustomSettings

    # Debug SQL connection issues
    $0 --sql -t 60

    # Debug configuration loading
    $0 --config -F

    # Debug with multiple channels and filter
    $0 -c file,reg,odbc -f "config\|key\|sql" -F

    # Full debug with no timeout
    $0 --full -t 0 -v

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--channels)
            CHANNELS="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        -l|--log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -F|--follow)
            FOLLOW_LOG=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --config)
            CHANNELS="file,reg,module"
            shift
            ;;
        --sql)
            CHANNELS="odbc,ole,reg"
            shift
            ;;
        --startup)
            CHANNELS="file,module,process"
            shift
            ;;
        --keys)
            CHANNELS="file,reg"
            FILTER_PATTERN="${FILTER_PATTERN:+$FILTER_PATTERN\|}key\|encryption\|Secret\|BC${BC_VERSION}"
            shift
            ;;
        --full)
            CHANNELS="file,reg,module,odbc,ole"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Use default channels if none specified
CHANNELS="${CHANNELS:-$DEFAULT_CHANNELS}"

# Create log directory in container
echo -e "${BLUE}Creating log directory...${NC}"
docker exec bcdevonlinux-bc-1 mkdir -p "$LOG_DIR"

# Generate log filename
LOG_FILE="$LOG_DIR/bc-wine-debug_${TIMESTAMP}_$(echo $CHANNELS | tr ',' '-').log"
FILTERED_LOG_FILE="$LOG_DIR/bc-wine-debug_${TIMESTAMP}_filtered.log"

echo -e "${GREEN}Wine Debug Configuration:${NC}"
echo "  Channels: $CHANNELS"
echo "  Timeout: ${TIMEOUT_SECONDS}s (0 = no timeout)"
echo "  Log file: $LOG_FILE"
[[ -n "$FILTER_PATTERN" ]] && echo "  Filter: $FILTER_PATTERN"
echo ""

# Kill any existing BC Server processes
echo -e "${YELLOW}Stopping existing BC Server processes...${NC}"
docker exec bcdevonlinux-bc-1 pkill -f "$BC_SERVER_EXE" 2>/dev/null || true
sleep 2

# Build the Wine command
WINE_CMD="cd '$BC_SERVER_PATH' && \
export WINEDEBUG=+$CHANNELS && \
export WINEPREFIX=/root/.local/share/wineprefixes/bc1 && \
export DISPLAY=:0"

if [[ $TIMEOUT_SECONDS -gt 0 ]]; then
    WINE_CMD="$WINE_CMD && timeout $TIMEOUT_SECONDS wine '$BC_SERVER_EXE' /console"
else
    WINE_CMD="$WINE_CMD && wine '$BC_SERVER_EXE' /console"
fi

# Add output redirection
WINE_CMD="$WINE_CMD 2>&1 | tee '$LOG_FILE'"

# Add filtering if specified
if [[ -n "$FILTER_PATTERN" ]]; then
    WINE_CMD="$WINE_CMD | grep -E '$FILTER_PATTERN' | tee '$FILTERED_LOG_FILE'"
fi

# Show command if verbose
if [[ "$VERBOSE" == true ]]; then
    echo -e "${BLUE}Executing command:${NC}"
    echo "$WINE_CMD"
    echo ""
fi

# Execute the command
echo -e "${GREEN}Starting BC Server with Wine debugging...${NC}"
if [[ "$FOLLOW_LOG" == true ]]; then
    # Run interactively to follow logs
    docker exec -it bcdevonlinux-bc-1 bash -c "$WINE_CMD"
else
    # Run in background
    docker exec -d bcdevonlinux-bc-1 bash -c "$WINE_CMD"
    echo -e "${GREEN}BC Server started in background with debugging enabled${NC}"
    echo ""
    echo -e "${YELLOW}To view logs:${NC}"
    echo "  Full log: docker exec bcdevonlinux-bc-1 tail -f '$LOG_FILE'"
    if [[ -n "$FILTER_PATTERN" ]]; then
        echo "  Filtered: docker exec bcdevonlinux-bc-1 tail -f '$FILTERED_LOG_FILE'"
    fi
fi

# Wait a moment for the process to start
sleep 3

# Check if BC is running
if docker exec bcdevonlinux-bc-1 pgrep -f "$BC_SERVER_EXE" > /dev/null; then
    echo -e "${GREEN}BC Server process is running${NC}"
else
    echo -e "${RED}BC Server process is not running${NC}"
    echo "Checking last 20 lines of log for errors:"
    docker exec bcdevonlinux-bc-1 tail -20 "$LOG_FILE" 2>/dev/null || echo "Log file not found"
fi

# Provide analysis commands
echo ""
echo -e "${BLUE}Useful analysis commands:${NC}"
echo ""
echo "# Count occurrences of specific operations:"
echo "docker exec bcdevonlinux-bc-1 grep -c 'CreateFile' '$LOG_FILE'"
echo ""
echo "# Find unique file access patterns:"
echo "docker exec bcdevonlinux-bc-1 grep 'file:.*name=' '$LOG_FILE' | sed 's/.*name=L\"//' | sed 's/\".*//' | sort -u"
echo ""
echo "# Find config file attempts:"
echo "docker exec bcdevonlinux-bc-1 grep -i 'customsettings\|\.config' '$LOG_FILE'"
echo ""
echo "# Find key file attempts:"
echo "docker exec bcdevonlinux-bc-1 grep -i '\.key\|encryption\|secret' '$LOG_FILE'"
echo ""
echo "# Find SQL/ODBC operations:"
echo "docker exec bcdevonlinux-bc-1 grep -E 'odbc:|ole:|sql' '$LOG_FILE'"
echo ""
echo "# Copy logs to host:"
echo "docker cp bcdevonlinux-bc-1:$LOG_FILE ./$(basename $LOG_FILE)"