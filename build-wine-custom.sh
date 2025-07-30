#!/bin/bash
# Build script for BC with custom Wine

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Business Central with custom Wine...${NC}"

# Check if wine patches directory exists and contains patches
if [ ! -d "wine-patches" ]; then
    echo -e "${RED}Error: wine-patches directory not found!${NC}"
    echo "Please ensure the wine-patches directory exists in the current directory."
    exit 1
fi

# Check if there are any .patch files in the directory
if ! ls wine-patches/*.patch >/dev/null 2>&1; then
    echo -e "${RED}Error: No patch files found in wine-patches directory!${NC}"
    echo "Please ensure at least one .patch file exists in wine-patches/"
    exit 1
fi

# Check specifically for the critical locale fix patch
if [ ! -f "wine-patches/001-wine-locale-display-fix.patch" ]; then
    echo -e "${YELLOW}Warning: 001-wine-locale-display-fix.patch not found in wine-patches/${NC}"
    echo "This patch is critical for Business Central locale support."
fi

# Show which patches will be applied
echo -e "${GREEN}Wine patches that will be applied:${NC}"
for patch in wine-patches/*.patch; do
    if [ -f "$patch" ]; then
        echo -e "  - $(basename "$patch")"
    fi
done | sort
echo ""

# Parse command line arguments
BUILD_ONLY=false
NO_CACHE=false
REBUILD_BC_ONLY=false
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
        --rebuild-bc-only)
            REBUILD_BC_ONLY=true
            shift
            ;;
        --no-sql)
            NO_SQL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --build-only      Only build the image, don't start containers"
            echo "  --no-cache        Build without using Docker cache"
            echo "  --rebuild-bc-only Rebuild only the BC stage (keeps Wine cache)"
            echo "  --no-sql          Use external SQL server (no SQL container)"
            echo "  --help            Show this help message"
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
    COMPOSE_FILE="compose-wine-custom-no-sql.yml"
    echo -e "${YELLOW}Using external SQL server configuration${NC}"
    
    # Check if SQL_SERVER is set
    if [ -z "$SQL_SERVER" ]; then
        echo -e "${RED}Warning: SQL_SERVER environment variable not set!${NC}"
        echo "Set it with: export SQL_SERVER=<your-sql-server-hostname>"
    fi
else
    COMPOSE_FILE="compose-wine-custom.yml"
fi

# Build command
BUILD_CMD="docker compose -f $COMPOSE_FILE build"

if [ "$NO_CACHE" = true ]; then
    BUILD_CMD="$BUILD_CMD --no-cache"
elif [ "$REBUILD_BC_ONLY" = true ]; then
    # Force rebuild of BC stage while keeping Wine builder cache
    echo -e "${YELLOW}Rebuilding only the BC stage (keeping Wine cache)...${NC}"
    BUILD_CMD="$BUILD_CMD --no-cache bc"
fi

if [ "$REBUILD_BC_ONLY" = true ]; then
    echo -e "${YELLOW}Starting Docker build (BC stage only)...${NC}"
    echo -e "${YELLOW}This will reuse the cached Wine build from the first stage${NC}"
else
    echo -e "${YELLOW}Starting Docker build...${NC}"
    echo -e "${YELLOW}Note: Wine compilation will take 20-30 minutes on first build${NC}"
fi

# Execute build
$BUILD_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build completed successfully!${NC}"
    
    if [ "$BUILD_ONLY" = false ]; then
        echo -e "${YELLOW}Starting containers...${NC}"
        docker compose -f $COMPOSE_FILE up -d
        
        echo -e "${GREEN}Containers started!${NC}"
        echo ""
        echo "To view logs:"
        echo "  docker compose -f $COMPOSE_FILE logs -f bc"
        echo ""
        echo "To check Wine version:"
        echo "  docker compose -f $COMPOSE_FILE exec bc wine --version"
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