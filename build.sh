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
DEV_MODE=false
DEV_OPTIMIZED=false

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
        -d|--dev)
            DEV_MODE=true
            shift
            ;;
        --dev-optimized)
            DEV_OPTIMIZED=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Default behavior: Builds image AND starts containers"
            echo ""
            echo "Options:"
            echo "  --build-only      Only build the image, don't start containers"
            echo "  --no-cache        Build without using Docker cache"
            echo "  --no-sql          Use external SQL server (no SQL container)"
            echo "  -d, --dev         Use locally built base image (bc-wine-base:local)"
            echo "  --dev-optimized   Use locally built optimized base image (bc-wine-base:local-optimized)"
            echo "  --help            Show this help message"
            echo ""
            echo "Options can be combined, e.g.: $0 --no-cache --build-only"
            echo ""
            echo "Build time comparison:"
            echo "  With base image:    ~5-10 minutes (vs 60-90 minutes before)"
            echo "  Startup time:       ~3-5 minutes (vs 15-20 minutes before)"
            echo ""
            echo "Compose files (auto-selected):"
            echo "  compose.yml           Default with local SQL container"
            echo "  compose-no-sql.yml    With --no-sql flag"
            echo ""
            echo "Environment variables for external SQL (--no-sql):"
            echo "  SQL_SERVER=<hostname>        Required: SQL server hostname/IP"
            echo "  SQL_SERVER_PORT=<port>       Optional: SQL port (default: 1433)"
            echo "  SA_PASSWORD=<password>       Required: SQL SA password"
            echo ""
            echo "Development workflow (testing base image changes):"
            echo "  Standard variant:"
            echo "    1. Build base image:       cd ~/BCOnLinuxBase && ./build-local.sh"
            echo "    2. Test in BCDevOnLinux:   cd ~/BCDevOnLinux-e036ace && ./build.sh --dev"
            echo "    3. Iterate and rebuild:    ./build.sh --dev --no-cache"
            echo "  Optimized variant:"
            echo "    1. Build base image:       cd ~/BCOnLinuxBase && ./build-local.sh --variant optimized"
            echo "    2. Test in BCDevOnLinux:   cd ~/BCDevOnLinux-e036ace && ./build.sh --dev-optimized"
            echo "    3. Iterate and rebuild:    ./build.sh --dev-optimized --no-cache"
            echo ""
            echo "Base image customization:"
            echo "  BASE_IMAGE=<image>           Override the base Docker image"
            echo "    Default:                   stefanmaronbc/bc-wine-base:latest"
            echo "  --dev flag sets:             bc-wine-base:local"
            echo "  --dev-optimized flag sets:   bc-wine-base:local-optimized"
            echo ""
            echo "Examples:"
            echo "  Development mode:            ./build.sh --dev"
            echo "  Dev optimized mode:          ./build.sh --dev-optimized"
            echo "  Dev with fresh build:        ./build.sh --dev --no-cache"
            echo "  Dev optimized fresh build:   ./build.sh --dev-optimized --no-cache"
            echo "  Dev build only:              ./build.sh --dev --build-only"
            echo "  Custom base image:           BASE_IMAGE=ubuntu:24.04 ./build.sh"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check for mutually exclusive flags
if [ "$DEV_MODE" = true ] && [ "$DEV_OPTIMIZED" = true ]; then
    echo -e "${RED}Error: --dev and --dev-optimized cannot be used together${NC}"
    echo "Choose one:"
    echo "  --dev           for bc-wine-base:local"
    echo "  --dev-optimized for bc-wine-base:local-optimized"
    exit 1
fi

# Handle dev mode - use locally built base image
if [ "$DEV_MODE" = true ]; then
    export BASE_IMAGE="bc-wine-base:local"
    echo -e "${YELLOW}Dev mode: Using locally built base image (bc-wine-base:local)${NC}"

    # Check if the local image exists
    if ! docker image inspect bc-wine-base:local &>/dev/null; then
        echo -e "${RED}Warning: bc-wine-base:local image not found!${NC}"
        echo -e "${YELLOW}Build it first with:${NC}"
        echo "  cd ~/BCOnLinuxBase && ./build-local.sh"
        echo ""
        exit 1
    fi
    echo ""
fi

# Handle dev-optimized mode - use locally built optimized base image
if [ "$DEV_OPTIMIZED" = true ]; then
    export BASE_IMAGE="bc-wine-base:local-optimized"
    echo -e "${YELLOW}Dev optimized mode: Using locally built optimized base image (bc-wine-base:local-optimized)${NC}"

    # Check if the local optimized image exists
    if ! docker image inspect bc-wine-base:local-optimized &>/dev/null; then
        echo -e "${RED}Warning: bc-wine-base:local-optimized image not found!${NC}"
        echo -e "${YELLOW}Build it first with:${NC}"
        echo "  cd ~/BCOnLinuxBase && ./build-local.sh --variant optimized"
        echo ""
        exit 1
    fi
    echo ""
fi

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

# Pull the latest base image (unless in dev or dev-optimized mode)
if [ "$DEV_MODE" != true ] && [ "$DEV_OPTIMIZED" != true ]; then
    BASE_IMAGE_TO_PULL="${BASE_IMAGE:-stefanmaronbc/bc-wine-base:latest}"
    echo -e "${YELLOW}Pulling latest base image: ${BASE_IMAGE_TO_PULL}${NC}"
    docker pull "$BASE_IMAGE_TO_PULL"
    echo ""
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