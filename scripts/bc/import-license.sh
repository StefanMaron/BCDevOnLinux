#!/bin/bash

set -e

echo "Checking Business Central license..."

# Environment variables
SQL_SERVER="${SQL_SERVER:-sql}"
SQL_PORT="${SQL_PORT:-1433}"
SA_PASSWORD="${SA_PASSWORD}"
# Try to get database name from CustomSettings.config if not set
if [ -z "$DATABASE_NAME" ] && [ -f "/home/CustomSettings.config" ]; then
    DATABASE_NAME=$(grep -oP '(?<=DatabaseName" value=")[^"]+' /home/CustomSettings.config 2>/dev/null || echo "")
fi
DATABASE_NAME="${DATABASE_NAME:-CRONUS}"

# License file location (static path from BC artifacts)
LICENSE_FILE="/home/bcartifacts/Cronus.bclicense"

# Add SQL tools to PATH if not already there
export PATH="$PATH:/opt/mssql-tools18/bin"

# Function to execute SQL commands
execute_sql() {
    local query="$1"
    sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -C -Q "$query" 2>&1
}

# Function to execute SQL commands with database context
execute_sql_db() {
    local query="$1"
    sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -d "$DATABASE_NAME" -C -Q "$query" 2>&1
}

# Check if database exists
echo "Checking if database '$DATABASE_NAME' exists..."
DB_EXISTS=$(execute_sql "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DATABASE_NAME') THEN 1 ELSE 0 END" | grep -o '[0-9]' | head -1)

if [ "$DB_EXISTS" != "1" ]; then
    echo "Database '$DATABASE_NAME' does not exist. Skipping license check."
    exit 0
fi

# Check if license is already present in database
echo "Checking for existing license in database..."
LICENSE_CHECK=$(execute_sql_db "SELECT CASE WHEN [license] IS NULL THEN 0 ELSE 1 END AS HasLicense FROM [\$ndo\$dbproperty]" | grep -o '[0-9]' | head -1)

if [ "$LICENSE_CHECK" = "1" ]; then
    LICENSE_SIZE=$(execute_sql_db "SELECT DATALENGTH([license]) AS LicenseSize FROM [\$ndo\$dbproperty]" | grep -o '[0-9]\+' | head -1)
    echo "License already present in database ($LICENSE_SIZE bytes). No import needed."
    exit 0
fi

echo "No license found in database. Looking for license file..."

# Check if license file exists
if [ ! -f "$LICENSE_FILE" ]; then
    echo "WARNING: License file not found at $LICENSE_FILE"
    echo "Business Central will run in demo mode with limitations."
    exit 0
fi

echo "Found license file: $LICENSE_FILE"

# Convert path for SQL Server (Docker volume mapping)
# /home/bcartifacts/* maps to /bc_artifacts/* in SQL Server container
LICENSE_FILE_SQL="${LICENSE_FILE/\/home\/bcartifacts/\/bc_artifacts}"

echo "Importing license from: $LICENSE_FILE"
echo "SQL Server path: $LICENSE_FILE_SQL"

# Import license using OPENROWSET
IMPORT_CMD="UPDATE [\$ndo\$dbproperty]
SET [license] = (
    SELECT BulkColumn
    FROM OPENROWSET(BULK '$LICENSE_FILE_SQL', SINGLE_BLOB) AS LicenseFile
)"

if execute_sql_db "$IMPORT_CMD" > /dev/null 2>&1; then
    # Verify import
    LICENSE_SIZE=$(execute_sql_db "SELECT DATALENGTH([license]) AS LicenseSize FROM [\$ndo\$dbproperty]" | grep -o '[0-9]\+' | head -1)

    if [ -n "$LICENSE_SIZE" ] && [ "$LICENSE_SIZE" -gt 0 ]; then
        echo "License imported successfully! ($LICENSE_SIZE bytes)"
        echo "NOTE: Restart Business Central Server to activate the license."
    else
        echo "ERROR: License import verification failed"
        exit 1
    fi
else
    echo "ERROR: Failed to import license"
    echo "Make sure:"
    echo "  1. The license file is accessible to SQL Server"
    echo "  2. The bcartifacts volume is mounted to both containers"
    echo "  3. SQL Server has BULK INSERT permissions"
    exit 1
fi
