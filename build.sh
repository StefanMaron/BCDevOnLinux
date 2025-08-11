#!/bin/bash
# Build script for BC with custom Wine

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Business Central with optimized base image...${NC}"
echo -e "${BLUE}Using stefanmaron/bc-wine-base which includes:${NC}"
echo -e "${BLUE}  ✓ Pre-compiled Wine with BC patches${NC}"
echo -e "${BLUE}  ✓ .NET Framework 4.8 pre-installed${NC}"
echo -e "${BLUE}  ✓ PowerShell & BC Container Helper${NC}"
echo -e "${BLUE}  ✓ Wine culture fixes applied${NC}"
echo ""

# Note: Wine patches are now pre-applied in the base image
echo -e "${GREEN}Wine patches already applied in base image:${NC}"
echo -e "  ✓ HTTP API functions for BC compatibility"
echo -e "  ✓ Locale fixes for culture enumeration"
echo -e "  ✓ Unicode generation improvements"
echo -e "  ✓ All BC-specific Wine optimizations"
echo ""

# Parse command line arguments
BUILD_ONLY=false
NO_CACHE=false
NO_SQL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --no-sql)
            NO_SQL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --build-only      Only build the image, don't start containers"
            echo "  --no-cache        Build without using Docker cache"
            echo "  --no-sql          Use external SQL server (no SQL container)"
            echo "  --help            Show this help message"
            echo ""
            echo "Build time comparison:"
            echo "  With base image:    ~5-10 minutes (vs 60-90 minutes before)"
            echo "  Startup time:       ~3-5 minutes (vs 15-20 minutes before)"
            echo ""
            echo "External SQL usage:"
            echo "  When using --no-sql, set these environment variables:"
            echo "    SQL_SERVER=<your-sql-server-hostname>"
            echo "    SQL_SERVER_PORT=<port> (default: 1433)"
            echo "    SA_PASSWORD=<sql-password>"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Determine which compose file to use
if [ "$NO_SQL" = true ]; then
    COMPOSE_FILE="compose-no-sql.yml"
    echo -e "${YELLOW}Using external SQL server configuration${NC}"
    
    # Check if SQL_SERVER is set
    if [ -z "$SQL_SERVER" ]; then
        echo -e "${RED}Warning: SQL_SERVER environment variable not set!${NC}"
        echo "Set it with: export SQL_SERVER=<your-sql-server-hostname>"
    fi
else
    COMPOSE_FILE="compose.yml"
fi

# Build command
BUILD_CMD="docker compose -f $COMPOSE_FILE build"

if [ "$NO_CACHE" = true ]; then
    BUILD_CMD="$BUILD_CMD --no-cache"
fi

echo -e "${YELLOW}Starting Docker build with base image...${NC}"
echo -e "${BLUE}Build optimizations:${NC}"
echo -e "${BLUE}  • Wine build: SKIPPED (pre-compiled in base)${NC}"
echo -e "${BLUE}  • .NET Framework 4.8: SKIPPED (pre-installed)${NC}"
echo -e "${BLUE}  • Only installing: BC artifacts + .NET 8 runtime${NC}"
echo -e "${YELLOW}Expected build time: ~5-10 minutes (vs 60-90 minutes without base)${NC}"

# Execute build
$BUILD_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build completed successfully!${NC}"
    
    if [ "$BUILD_ONLY" = false ]; then
        echo -e "${YELLOW}Starting containers...${NC}"
        docker compose -f $COMPOSE_FILE up -d
        
        echo -e "${GREEN}Containers started!${NC}"
        echo ""
        echo -e "${BLUE}Performance improvements:${NC}"
        echo -e "${BLUE}  • Startup time: ~3-5 minutes (vs 15-20 minutes)${NC}"
        echo -e "${BLUE}  • Build time: ~5-10 minutes (vs 60-90 minutes)${NC}"
        echo ""
        echo "To view logs:"
        echo "  docker compose -f $COMPOSE_FILE logs -f bc"
        echo ""
        echo "To check Wine version:"
        echo "  docker compose -f $COMPOSE_FILE exec bc wine --version"
        echo ""
        echo "To check .NET installations:"
        echo "  docker compose -f $COMPOSE_FILE exec bc pwsh -c 'Get-ChildItem \"C:\\Program Files\\dotnet\"'"
        echo ""
        
        if [ "$NO_SQL" = true ]; then
            echo ""
            echo -e "${YELLOW}External SQL Configuration:${NC}"
            echo "  SQL_SERVER=${SQL_SERVER:-not set}"
            echo "  SQL_SERVER_PORT=${SQL_SERVER_PORT:-1433}"
            echo ""
            echo "Make sure your external SQL server is accessible from this container."
        fi
    fi
else
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi