#!/bin/bash

set -e

echo "Building BC Development on Linux (BC4Ubuntu approach)"
echo "======================================================"

# Build the container
echo "Building Docker container..."
docker build -t bc-linux-bc4ubuntu .

echo ""
echo "Container built successfully!"
echo ""
echo "To run the container with SQL Server:"
echo "  docker-compose up"
echo ""
echo "IMPORTANT: If BC Server fails with '.NET 8.0 not found':"
echo "  1. Download .NET 8.0 hosting bundle from: https://dotnet.microsoft.com/download/dotnet/8.0"
echo "  2. Run: docker exec -it <container_name> /home/install-dotnet8-hosting.sh"
echo "  3. Follow the manual installation instructions"
echo ""
echo "To run interactive setup:"
echo "  docker run -it bc-linux-bc4ubuntu /home/setup-wine-interactive.sh"
echo ""
echo "To test Wine installation:"
echo "  docker run -it bc-linux-bc4ubuntu bash"
echo "  # Then inside container:"
echo "  export WINEPREFIX=~/.local/share/wineprefixes/bc1"
echo "  wine --version"
echo ""
echo "Based on BC4Ubuntu methodology: https://github.com/SShadowS/BC4Ubuntu"
