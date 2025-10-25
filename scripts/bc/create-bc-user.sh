#!/bin/bash

# Business Central User Creation via Direct SQL
# This is a wrapper for create-bc-user-sql.sh which uses BC's exact password hashing algorithm

set -e

USERNAME=${1:-"admin"}
PASSWORD=${2:-"${SA_PASSWORD:-P@ssw0rd123!}"}
PERMISSION_SET=${3:-"SUPER"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure BCPasswordHasher is built
if [ ! -f "$SCRIPT_DIR/BCPasswordHasher/bin/Release/net8.0/BCPasswordHasher.dll" ] && [ ! -f "$SCRIPT_DIR/BCPasswordHasher/bin/Debug/net8.0/BCPasswordHasher.dll" ]; then
    echo "Building BCPasswordHasher..."
    if command -v dotnet &> /dev/null; then
        dotnet build "$SCRIPT_DIR/BCPasswordHasher/BCPasswordHasher.csproj" -c Release > /dev/null 2>&1 || \
        dotnet build "$SCRIPT_DIR/BCPasswordHasher/BCPasswordHasher.csproj" > /dev/null 2>&1
    else
        echo "ERROR: .NET SDK not found. Cannot build BCPasswordHasher."
        exit 1
    fi
fi

# Call SQL-based user creation script
exec "$SCRIPT_DIR/create-bc-user-sql.sh" "$USERNAME" "$PASSWORD" "$PERMISSION_SET"
