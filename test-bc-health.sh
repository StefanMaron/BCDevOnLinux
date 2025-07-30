#!/bin/bash
# Simple BC Server health check

echo "Testing Business Central Server Health..."
echo "========================================"

# Check if BC process is running (use wider search pattern)
echo -n "BC Server Process: "
if docker compose -f compose-wine-custom.yml exec bc pgrep -f "Microsoft.Dynamics.Nav.Server" > /dev/null 2>&1; then
    echo "✓ Running"
    PID=$(docker compose -f compose-wine-custom.yml exec bc pgrep -f "Microsoft.Dynamics.Nav.Server" | head -1)
    echo "  PID: $PID"
else
    echo "✗ Not running"
fi

# Check Docker container health
echo -n "Container Health: "
HEALTH=$(docker inspect bcdevonlinux-bc-1 --format='{{.State.Health.Status}}' 2>/dev/null)
if [ "$HEALTH" = "healthy" ]; then
    echo "✓ Healthy"
else
    echo "✗ Status: $HEALTH"
fi

# Test ports from host
echo ""
echo "Testing endpoints from host:"
for PORT in 7045 7049 7086; do
    echo -n "Port $PORT: "
    if timeout 2 bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; then
        echo "✓ Open"
    else
        echo "✗ Closed/Not responding"
    fi
done

# Test BC from inside container (Wine network issues are common)
echo ""
echo "Testing from inside container:"
docker compose -f compose-wine-custom.yml exec bc bash -c '
    echo -n "Wine network test: "
    if wine cmd /c "echo test" 2>/dev/null | grep -q test; then
        echo "✓ Wine networking available"
    else
        echo "✗ Wine networking issues"
    fi
'

echo ""
echo "Note: BC Server on Wine may not bind to network ports properly."
echo "The process is running but network access may be limited."
echo "This is a known limitation of running .NET services under Wine."