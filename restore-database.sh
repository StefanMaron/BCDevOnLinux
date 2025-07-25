#!/bin/bash

set -e

echo "Checking if database needs to be restored..."

# Environment variables
SQL_SERVER="${SQL_SERVER:-sql}"
SQL_PORT="${SQL_PORT:-1433}"
SA_PASSWORD="${SA_PASSWORD}"
# Try to get database name from CustomSettings.config if not set
if [ -z "$DATABASE_NAME" ] && [ -f "/home/CustomSettings.config" ]; then
    DATABASE_NAME=$(grep -oP '(?<=DatabaseName" value=")[^"]+' /home/CustomSettings.config 2>/dev/null || echo "")
fi

DATABASE_NAME="${DATABASE_NAME:-CRONUS}"

# Find the backup file in /home/bcartifacts
BACKUP_FILE=$(find /home/bcartifacts -name "*.bak" -type f | head -1)

# Add SQL tools to PATH if not already there
export PATH="$PATH:/opt/mssql-tools18/bin"

# Function to execute SQL commands
execute_sql() {
    local query="$1"
    sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -C -Q "$query" 2>&1
}

# Wait for SQL Server to be ready
echo "Waiting for SQL Server to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if execute_sql "SELECT 1" > /dev/null 2>&1; then
        echo "SQL Server is ready"
        break
    fi
    echo "Waiting for SQL Server... (attempt $((ATTEMPT+1))/$MAX_ATTEMPTS)"
    sleep 2
    ATTEMPT=$((ATTEMPT+1))
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "ERROR: SQL Server is not responding after $MAX_ATTEMPTS attempts"
    exit 1
fi

# Check if database already exists
echo "Checking if database '$DATABASE_NAME' exists..."
DB_EXISTS=$(execute_sql "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DATABASE_NAME') THEN 1 ELSE 0 END" | grep -o '[0-9]' | head -1)

if [ "$DB_EXISTS" = "1" ]; then
    echo "Database '$DATABASE_NAME' already exists. Skipping restore."
    exit 0
fi

# Check if backup file exists
if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "WARNING: No .bak file found in /home/bcartifacts/"
    echo "Creating empty database '$DATABASE_NAME'..."
    execute_sql "CREATE DATABASE [$DATABASE_NAME]"
    echo "Empty database created."
    exit 0
fi

echo "Found backup file: $BACKUP_FILE"
echo "Restoring database from backup..."

# Get logical file names from backup
echo "Reading backup file information..."
FILELISTONLY=$(execute_sql "RESTORE FILELISTONLY FROM DISK = N'$BACKUP_FILE'")

echo "Debug: FILELISTONLY output:"
echo "$FILELISTONLY"

# Extract logical names with more robust patterns
DATA_LOGICAL_NAME=$(echo "$FILELISTONLY" | grep -i "\.mdf" | awk '{print $1}' | head -1)
LOG_LOGICAL_NAME=$(echo "$FILELISTONLY" | grep -i "\.ldf" | awk '{print $1}' | head -1)

# If the above doesn't work, try alternative patterns
if [ -z "$DATA_LOGICAL_NAME" ]; then
    DATA_LOGICAL_NAME=$(echo "$FILELISTONLY" | grep -E "ROWS|D|Data" | head -1 | awk '{print $1}')
fi

if [ -z "$LOG_LOGICAL_NAME" ]; then
    LOG_LOGICAL_NAME=$(echo "$FILELISTONLY" | grep -E "LOG|L|Log" | head -1 | awk '{print $1}')
fi

if [ -z "$DATA_LOGICAL_NAME" ] || [ -z "$LOG_LOGICAL_NAME" ]; then
    echo "ERROR: Could not determine logical file names from backup"
    echo "Available files in backup:"
    echo "$FILELISTONLY"
    exit 1
fi

echo "Data file: $DATA_LOGICAL_NAME"
echo "Log file: $LOG_LOGICAL_NAME"

# Restore the database
echo "Executing database restore..."
RESTORE_CMD="RESTORE DATABASE [$DATABASE_NAME] 
FROM DISK = N'$BACKUP_FILE' 
WITH MOVE N'$DATA_LOGICAL_NAME' TO N'/var/opt/mssql/data/${DATABASE_NAME}.mdf',
MOVE N'$LOG_LOGICAL_NAME' TO N'/var/opt/mssql/data/${DATABASE_NAME}.ldf',
REPLACE"

if execute_sql "$RESTORE_CMD"; then
    echo "Database '$DATABASE_NAME' restored successfully!"
    
    # Verify the restore
    DB_STATE=$(execute_sql "SELECT state_desc FROM sys.databases WHERE name = '$DATABASE_NAME'" | grep -E "ONLINE|OFFLINE" | tr -d ' ')
    echo "Database state: $DB_STATE"
    
    if [ "$DB_STATE" = "ONLINE" ]; then
        echo "Database is online and ready to use"
    else
        echo "WARNING: Database is not in ONLINE state"
    fi
else
    echo "ERROR: Database restore failed"
    exit 1
fi

echo "Database restoration completed successfully"