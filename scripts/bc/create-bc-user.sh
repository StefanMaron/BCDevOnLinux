#!/bin/bash

# Bash wrapper for creating BC users
# Usage: create-bc-user.sh [username] [password] [permission_set]

set -e

USERNAME=${1:-"admin"}
PASSWORD=${2:-"${SA_PASSWORD:-P@ssw0rd123!}"}
PERMISSION_SET=${3:-"SUPER"}

echo "Creating Business Central user with NavUserPassword authentication..."
echo "Username: $USERNAME"
echo "Permission Set: $PERMISSION_SET"

# Call PowerShell script
pwsh /home/scripts/bc/create-bc-user.ps1 -Username "$USERNAME" -Password "$PASSWORD" -PermissionSetId "$PERMISSION_SET"

echo "User creation completed."