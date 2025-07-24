#!/bin/bash
# Build script for BC with custom Wine

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Business Central with custom Wine...${NC}"

# Check if wine-locale-display-fix.patch exists
if [ ! -f "wine-locale-display-fix.patch" ]; then
    echo -e "${RED}Error: wine-locale-display-fix.patch not found!${NC}"
    echo "Please ensure the locale fix patch is in the current directory."
    exit 1
fi

# Parse command line arguments
BUILD_ONLY=false
NO_CACHE=false

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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --build-only    Only build the image, don't start containers"
            echo "  --no-cache      Build without using Docker cache"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Build command
BUILD_CMD="docker compose -f compose-wine-custom.yml build"

if [ "$NO_CACHE" = true ]; then
    BUILD_CMD="$BUILD_CMD --no-cache"
fi

echo -e "${YELLOW}Starting Docker build...${NC}"
echo -e "${YELLOW}Note: Wine compilation will take 20-30 minutes on first build${NC}"

# Execute build
$BUILD_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build completed successfully!${NC}"
    
    if [ "$BUILD_ONLY" = false ]; then
        echo -e "${YELLOW}Starting containers...${NC}"
        docker compose -f compose-wine-custom.yml up -d
        
        echo -e "${GREEN}Containers started!${NC}"
        echo ""
        echo "To view logs:"
        echo "  docker compose -f compose-wine-custom.yml logs -f bc"
        echo ""
        echo "To check Wine version:"
        echo "  docker compose -f compose-wine-custom.yml exec bc wine --version"
        echo ""
        echo "To test locale fixes:"
        echo "  docker compose -f compose-wine-custom.yml exec bc /home/test-wine-locale.sh"
    fi
else
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi