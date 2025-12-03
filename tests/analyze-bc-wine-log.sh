#!/bin/bash
# Analyze Wine debug logs for BC Server

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default log directory
LOG_DIR="/home/bc-debug-logs"

usage() {
    cat << EOF
Usage: $0 [LOG_FILE] [OPTIONS]

Analyze Wine debug logs for BC Server issues

OPTIONS:
    -s, --summary              Show summary statistics
    -c, --config               Analyze configuration file access
    -k, --keys                 Analyze encryption key access
    -q, --sql                  Analyze SQL/database operations
    -f, --files                List all unique files accessed
    -e, --errors               Show errors and warnings
    -t, --timeline             Show timeline of operations
    -p, --pattern PATTERN      Search for specific pattern
    -h, --help                 Show this help message

If no log file is specified, analyzes the most recent log in $LOG_DIR

EXAMPLES:
    # Analyze most recent log with summary
    $0 -s
    
    # Analyze specific log for config issues
    $0 /home/bc-debug-logs/bc-wine-debug_20240125_123456.log -c
    
    # Search for specific pattern
    $0 -p "CustomSettings"

EOF
}

# Find most recent log file
find_latest_log() {
    docker exec bcdevonlinux-bc-1 bash -c "ls -t $LOG_DIR/bc-wine-debug_*.log 2>/dev/null | head -1"
}

# Parse arguments
LOG_FILE=""
SHOW_SUMMARY=false
SHOW_CONFIG=false
SHOW_KEYS=false
SHOW_SQL=false
SHOW_FILES=false
SHOW_ERRORS=false
SHOW_TIMELINE=false
SEARCH_PATTERN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--summary)
            SHOW_SUMMARY=true
            shift
            ;;
        -c|--config)
            SHOW_CONFIG=true
            shift
            ;;
        -k|--keys)
            SHOW_KEYS=true
            shift
            ;;
        -q|--sql)
            SHOW_SQL=true
            shift
            ;;
        -f|--files)
            SHOW_FILES=true
            shift
            ;;
        -e|--errors)
            SHOW_ERRORS=true
            shift
            ;;
        -t|--timeline)
            SHOW_TIMELINE=true
            shift
            ;;
        -p|--pattern)
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$LOG_FILE" && ! "$1" =~ ^- ]]; then
                LOG_FILE="$1"
            else
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# If no specific analysis requested, show summary
if [[ "$SHOW_SUMMARY" == false && "$SHOW_CONFIG" == false && "$SHOW_KEYS" == false && \
      "$SHOW_SQL" == false && "$SHOW_FILES" == false && "$SHOW_ERRORS" == false && \
      "$SHOW_TIMELINE" == false && -z "$SEARCH_PATTERN" ]]; then
    SHOW_SUMMARY=true
fi

# Find log file if not specified
if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE=$(find_latest_log)
    if [[ -z "$LOG_FILE" ]]; then
        echo -e "${RED}No log files found in $LOG_DIR${NC}"
        exit 1
    fi
    echo -e "${BLUE}Using most recent log: $LOG_FILE${NC}"
fi

# Check if log file exists
if ! docker exec bcdevonlinux-bc-1 test -f "$LOG_FILE"; then
    echo -e "${RED}Log file not found: $LOG_FILE${NC}"
    exit 1
fi

echo ""

# Summary statistics
if [[ "$SHOW_SUMMARY" == true ]]; then
    echo -e "${GREEN}=== Summary Statistics ===${NC}"
    
    TOTAL_LINES=$(docker exec bcdevonlinux-bc-1 wc -l < "$LOG_FILE")
    echo "Total log lines: $TOTAL_LINES"
    
    echo ""
    echo "Channel activity:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -oE '^[0-9a-f]+:trace:[a-z]+:' '$LOG_FILE' | cut -d: -f3 | sort | uniq -c | sort -rn | head -10"
    
    echo ""
    echo "Most accessed paths:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -oE 'L\"[^\"]+\"' '$LOG_FILE' | sed 's/L\"//' | sed 's/\"//' | sort | uniq -c | sort -rn | head -10"
    echo ""
fi

# Configuration file analysis
if [[ "$SHOW_CONFIG" == true ]]; then
    echo -e "${GREEN}=== Configuration File Analysis ===${NC}"
    
    echo "Searching for config file access patterns..."
    docker exec bcdevonlinux-bc-1 bash -c "grep -iE 'customsettings|\.config|configuration' '$LOG_FILE' | grep -v '\.dll' | head -20"
    
    echo ""
    echo "Config-related registry access:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E 'reg:.*config' '$LOG_FILE' | head -10"
    echo ""
fi

# Encryption key analysis
if [[ "$SHOW_KEYS" == true ]]; then
    echo -e "${GREEN}=== Encryption Key Analysis ===${NC}"
    
    echo "Key file access attempts:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -iE '\.key|secret|encryption|BC[0-9]+|Keys' '$LOG_FILE' | grep -E 'file:|reg:' | head -20"
    
    echo ""
    echo "ProgramData key locations:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E 'ProgramData.*Microsoft.*Nav.*Key' '$LOG_FILE' | head -10"
    echo ""
fi

# SQL/Database analysis
if [[ "$SHOW_SQL" == true ]]; then
    echo -e "${GREEN}=== SQL/Database Analysis ===${NC}"
    
    echo "ODBC operations:"
    docker exec bcdevonlinux-bc-1 bash -c "grep 'odbc:' '$LOG_FILE' | head -20"
    
    echo ""
    echo "OLE/COM operations:"
    docker exec bcdevonlinux-bc-1 bash -c "grep 'ole:' '$LOG_FILE' | head -20"
    
    echo ""
    echo "SQL-related file access:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -iE 'sql|odbc|oledb' '$LOG_FILE' | grep 'file:' | head -10"
    echo ""
fi

# File listing
if [[ "$SHOW_FILES" == true ]]; then
    echo -e "${GREEN}=== Unique Files Accessed ===${NC}"
    
    echo "Extracting unique file paths..."
    docker exec bcdevonlinux-bc-1 bash -c "
        grep -oE 'name=L\"[^\"]+\"' '$LOG_FILE' | \
        sed 's/name=L\"//' | sed 's/\"//' | \
        grep -v '^C:\\\\windows\\\\system32' | \
        sort -u | \
        head -50
    "
    echo ""
fi

# Errors and warnings
if [[ "$SHOW_ERRORS" == true ]]; then
    echo -e "${GREEN}=== Errors and Warnings ===${NC}"
    
    echo "Wine errors:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E 'err:|ERR:|error' '$LOG_FILE' | head -20"
    
    echo ""
    echo "Wine warnings:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E 'warn:|WARN:|warning' '$LOG_FILE' | head -20"
    
    echo ""
    echo "File not found:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E 'not found|c0000034|c0000035' '$LOG_FILE' | head -20"
    echo ""
fi

# Timeline
if [[ "$SHOW_TIMELINE" == true ]]; then
    echo -e "${GREEN}=== Operation Timeline ===${NC}"
    
    echo "First 50 operations:"
    docker exec bcdevonlinux-bc-1 bash -c "grep -E '^[0-9a-f]+:' '$LOG_FILE' | head -50"
    echo ""
fi

# Pattern search
if [[ -n "$SEARCH_PATTERN" ]]; then
    echo -e "${GREEN}=== Pattern Search: $SEARCH_PATTERN ===${NC}"
    
    MATCHES=$(docker exec bcdevonlinux-bc-1 grep -c "$SEARCH_PATTERN" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "Found $MATCHES matches"
    echo ""
    
    if [[ $MATCHES -gt 0 ]]; then
        echo "First 20 matches:"
        docker exec bcdevonlinux-bc-1 grep --color=never "$SEARCH_PATTERN" "$LOG_FILE" | head -20
    fi
    echo ""
fi

# Provide next steps
echo -e "${CYAN}=== Analysis Tips ===${NC}"
echo "1. If no config file access found, BC may be using hardcoded paths"
echo "2. Check for 'not found' errors to see missing dependencies"
echo "3. Look for registry access patterns for configuration"
echo "4. ODBC errors often indicate SQL connection issues"
echo "5. Missing key files prevent encrypted password usage"