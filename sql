#!/bin/bash

# Wrapper script for executing commands in the SQL container

# Detect which compose file to use
if [ -f "compose-wine-custom.yml" ]; then
    COMPOSE_FILE="compose-wine-custom.yml"
elif [ -f "compose.yml" ]; then
    COMPOSE_FILE="compose.yml"
else
    echo "Error: No compose file found!"
    exit 1
fi

# Parse options
INTERACTIVE=""
while [[ $# -gt 0 ]] && [[ "$1" == -* ]]; do
    case "$1" in
        -i|--interactive)
            INTERACTIVE="-it"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [COMMAND]"
            echo ""
            echo "Execute commands in the SQL container"
            echo ""
            echo "Options:"
            echo "  -i, --interactive    Run interactively (allocate TTY)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                          # Interactive bash shell"
            echo "  $0 -i sqlcmd                # Interactive sqlcmd"
            echo "  $0 sqlcmd -Q \"SELECT @@VERSION\"  # Run SQL query"
            echo ""
            echo "Note: sqlcmd connects with SA password from environment"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if container is running
if ! docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -q "^sql$"; then
    echo "Error: SQL container is not running!"
    echo "Start it with: docker compose -f $COMPOSE_FILE up -d sql"
    exit 1
fi

# Get SA password from environment or use default
SA_PASSWORD="${SA_PASSWORD:-P@ssw0rd123!}"

# If no command provided, default to interactive bash
if [ $# -eq 0 ]; then
    exec docker compose -f "$COMPOSE_FILE" exec -it sql bash
else
    # Special handling for sqlcmd to include authentication
    if [ "$1" = "sqlcmd" ] && [ "$2" != "-?" ] && [ "$2" != "--help" ]; then
        # Add authentication parameters if not already present
        shift # remove 'sqlcmd'
        exec docker compose -f "$COMPOSE_FILE" exec $INTERACTIVE -e SQLCMDPASSWORD="$SA_PASSWORD" sql \
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -N "$@"
    else
        # Execute the provided command as-is
        exec docker compose -f "$COMPOSE_FILE" exec $INTERACTIVE sql "$@"
    fi
fi