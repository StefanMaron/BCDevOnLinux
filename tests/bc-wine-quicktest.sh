#!/bin/bash
# Quick test script for BC Wine debugging

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== BC Wine Quick Test ===${NC}"
echo ""

# Test 1: Configuration file access
echo -e "${YELLOW}Test 1: Checking configuration file access...${NC}"
./debug-bc-wine.sh --config -t 15 -f "CustomSettings\|\.config"
sleep 5
echo ""

# Analyze results
echo -e "${GREEN}Analyzing configuration access:${NC}"
LOG_FILE=$(docker exec bcdevonlinux-bc-1 ls -t /home/bc-debug-logs/bc-wine-debug_*.log 2>/dev/null | head -1)
if [[ -n "$LOG_FILE" ]]; then
    echo "Config file searches:"
    docker exec bcdevonlinux-bc-1 grep -i "customsettings" "$LOG_FILE" | wc -l
    echo ""
    echo "Sample config searches:"
    docker exec bcdevonlinux-bc-1 grep -i "customsettings" "$LOG_FILE" | head -5
fi

echo ""
echo -e "${YELLOW}Test 2: Checking encryption key access...${NC}"
./debug-bc-wine.sh --keys -t 15
sleep 5

echo ""
echo -e "${GREEN}Analyzing key access:${NC}"
LOG_FILE=$(docker exec bcdevonlinux-bc-1 ls -t /home/bc-debug-logs/bc-wine-debug_*.log 2>/dev/null | head -1)
if [[ -n "$LOG_FILE" ]]; then
    echo "Key file searches:"
    docker exec bcdevonlinux-bc-1 grep -iE "\.key|secret|BC[0-9]+" "$LOG_FILE" | wc -l
    echo ""
    echo "Sample key searches:"
    docker exec bcdevonlinux-bc-1 grep -iE "\.key|secret|BC[0-9]+" "$LOG_FILE" | head -5
fi

echo ""
echo -e "${BLUE}Quick test complete. For detailed analysis, run:${NC}"
echo "./analyze-bc-wine-log.sh -s -c -k"