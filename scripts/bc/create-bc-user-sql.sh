#!/bin/bash
set -e

###############################################################################
# Business Central User Creation via Direct SQL
#
# WARNING: This script bypasses BC's official APIs and directly modifies
# the database. Use at your own risk - may cause:
#   - Database corruption
#   - Cache incoherence
#   - Broken audit trails
#   - Version incompatibility
#   - Loss of Microsoft support
#
# Only use in development/testing environments where you accept these risks.
#
# Requirements:
#   - Python 3 with hashlib
#   - sqlcmd (SQL Server command-line tool)
#   - Network access to SQL Server
#
# Usage:
#   create-bc-user-sql.sh <username> <password> [permission_set]
#
# Example:
#   create-bc-user-sql.sh admin "P@ssw0rd123" SUPER
###############################################################################

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_PERMISSION_SET="SUPER"
SQL_SERVER="${SQL_SERVER:-sql}"
SQL_PORT="${SQL_PORT:-1433}"
SA_PASSWORD="${SA_PASSWORD:-P@ssw0rd123!}"
DATABASE="${DATABASE:-BC}"

# ANSI colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
if [ $# -lt 2 ]; then
    log_error "Insufficient arguments"
    echo ""
    echo "Usage: $0 <username> <password> [permission_set]"
    echo ""
    echo "Arguments:"
    echo "  username        - BC username (alphanumeric, max 50 chars)"
    echo "  password        - Password (must meet BC complexity requirements)"
    echo "  permission_set  - Optional, defaults to 'SUPER'"
    echo ""
    echo "Example:"
    echo "  $0 admin 'P@ssw0rd123' SUPER"
    echo ""
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"
PERMISSION_SET="${3:-$DEFAULT_PERMISSION_SET}"

# Display warning
echo ""
log_warn "═══════════════════════════════════════════════════════════════"
log_warn "  UNSUPPORTED OPERATION - PROCEED AT YOUR OWN RISK"
log_warn "═══════════════════════════════════════════════════════════════"
log_warn "This script directly modifies the BC database bypassing all"
log_warn "official APIs. Microsoft Support will NOT assist with issues"
log_warn "caused by this script."
log_warn ""
log_warn "Risks: Database corruption, cache issues, audit trail gaps,"
log_warn "        version incompatibility, security vulnerabilities"
log_warn "═══════════════════════════════════════════════════════════════"
echo ""

# Validate username
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid username: must contain only alphanumeric characters, underscores, and hyphens"
    exit 1
fi

if [ ${#USERNAME} -gt 50 ]; then
    log_error "Username too long: maximum 50 characters"
    exit 1
fi

# Check Python availability
if ! command -v python3 &> /dev/null; then
    log_error "Python 3 is required but not installed"
    exit 1
fi

# Check sqlcmd availability
if ! command -v /opt/mssql-tools18/bin/sqlcmd &> /dev/null; then
    log_error "sqlcmd is required but not found"
    log_info "Install with: apt-get install mssql-tools18"
    exit 1
fi

log_info "Creating BC user: $USERNAME"
log_info "Permission Set: $PERMISSION_SET"
log_info "Database: $DATABASE on $SQL_SERVER:$SQL_PORT"
echo ""

# Step 1: Generate new user GUIDs
log_info "Step 1/5: Generating user GUIDs..."
USER_GUID=$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")
TELEMETRY_GUID=$(python3 -c "import uuid; print(str(uuid.uuid4()).upper())")
log_success "Generated User GUID: $USER_GUID"
log_success "Generated Telemetry GUID: $TELEMETRY_GUID"

# Step 2: Check if user already exists
log_info "Step 2/5: Checking for existing user..."
EXISTING_USER=$(/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -d "$DATABASE" -C -N -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM [dbo].[User] WHERE [User Name] = '$USERNAME'" 2>/dev/null | tr -d '[:space:]')

if [ "$EXISTING_USER" != "0" ]; then
    log_error "User '$USERNAME' already exists"
    exit 1
fi
log_success "Username is available"

# Step 3: Generate password hash
log_info "Step 3/5: Hashing password..."

# Determine which BCPasswordHasher binary to use
HASHER_BIN=""
if [ -f "$SCRIPT_DIR/BCPasswordHasher/bin/Release/net8.0/BCPasswordHasher" ]; then
    HASHER_BIN="$SCRIPT_DIR/BCPasswordHasher/bin/Release/net8.0/BCPasswordHasher"
elif [ -f "$SCRIPT_DIR/BCPasswordHasher/bin/Debug/net8.0/BCPasswordHasher" ]; then
    HASHER_BIN="$SCRIPT_DIR/BCPasswordHasher/bin/Debug/net8.0/BCPasswordHasher"
elif [ -f "$SCRIPT_DIR/BCPasswordHasher/bin/Release/net8.0/BCPasswordHasher.dll" ]; then
    HASHER_BIN="dotnet $SCRIPT_DIR/BCPasswordHasher/bin/Release/net8.0/BCPasswordHasher.dll"
elif [ -f "$SCRIPT_DIR/BCPasswordHasher/bin/Debug/net8.0/BCPasswordHasher.dll" ]; then
    HASHER_BIN="dotnet $SCRIPT_DIR/BCPasswordHasher/bin/Debug/net8.0/BCPasswordHasher.dll"
else
    log_error "BCPasswordHasher binary not found"
    log_error "Expected at: $SCRIPT_DIR/BCPasswordHasher/bin/{Release|Debug}/net8.0/BCPasswordHasher"
    exit 1
fi

# Generate password hash using BC's exact algorithm
PASSWORD_HASH=$($HASHER_BIN "$PASSWORD" "$USER_GUID" 2>&1)
HASH_EXIT_CODE=$?

if [ $HASH_EXIT_CODE -ne 0 ] || [ -z "$PASSWORD_HASH" ]; then
    log_error "Failed to generate password hash"
    log_error "BCPasswordHasher output: $PASSWORD_HASH"
    log_error "Using: $HASHER_BIN"
    exit 1
fi
log_success "Password hashed successfully (${PASSWORD_HASH:0:20}...)"

# Step 4: Execute SQL transaction
log_info "Step 4/5: Inserting user into database..."

# Escape single quotes in strings for SQL
SQL_USERNAME="${USERNAME//\'/\'\'}"
SQL_PASSWORD_HASH="${PASSWORD_HASH//\'/\'\'}"

# Create SQL script
SQL_SCRIPT="
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Insert into User table (2000000120)
INSERT INTO [dbo].[User] (
    [User Security ID],
    [User Name],
    [Full Name],
    [State],
    [Expiry Date],
    [Windows Security ID],
    [Change Password],
    [License Type],
    [Authentication Email],
    [Contact Email],
    [Application ID],
    [Exchange Identifier]
) VALUES (
    '$USER_GUID',
    '$SQL_USERNAME',
    '$SQL_USERNAME',
    0,  -- State: 0=Enabled
    '1753-01-01',  -- No expiry
    '',  -- Empty for NavUserPassword
    0,  -- Don't force password change
    0,  -- License Type: 0=Full User
    '',  -- Authentication Email (optional)
    '',  -- Contact Email (optional)
    '00000000-0000-0000-0000-000000000000',  -- Application ID
    ''  -- Exchange Identifier (required, empty for NavUserPassword)
);

-- Insert into User Property table (2000000121)
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'User Property')
BEGIN
    INSERT INTO [dbo].[User Property] (
        [User Security ID],
        [Password],
        [Name Identifier],
        [Authentication Key],
        [WebServices Key],
        [WebServices Key Expiry Date],
        [Authentication Object ID],
        [Directory Role ID],
        [Telemetry User ID]
    ) VALUES (
        '$USER_GUID',
        '$SQL_PASSWORD_HASH',
        '',  -- Name Identifier (empty for NavUserPassword)
        '',  -- Authentication Key (empty for password auth)
        '',  -- WebServices Key (not generated automatically)
        '1753-01-01',  -- WebServices Key Expiry Date (no expiry)
        '',  -- Authentication Object ID (empty for NavUserPassword)
        '',  -- Directory Role ID (empty for local users)
        '$TELEMETRY_GUID'  -- Telemetry User ID (unique per user)
    );
END

-- Assign permission set via Access Control
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Access Control')
BEGIN
    INSERT INTO [dbo].[Access Control] (
        [User Security ID],
        [Role ID],
        [Company Name],
        [Scope],
        [App ID]
    ) VALUES (
        '$USER_GUID',
        '$PERMISSION_SET',
        '',  -- Empty = all companies
        0,  -- Scope: 0=System
        '00000000-0000-0000-0000-000000000000'  -- System App
    );
END

-- Insert User Personalization (CRITICAL for authentication)
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'User Personalization')
BEGIN
    INSERT INTO [dbo].[User Personalization] (
        [User SID],
        [Profile ID],
        [App ID],
        [Scope],
        [Language ID],
        [Company],
        [Debugger Break On Error],
        [Debugger Break On Rec Changes],
        [Debugger Skip System Triggers],
        [Locale ID],
        [Time Zone],
        [Customization Status],
        [Emit Version]
    ) VALUES (
        '$USER_GUID',
        'BUSINESS MANAGER',  -- Standard BC profile for business users
        '437DBF0E-84FF-417A-965D-ED2BB9650972',  -- System App ID
        1,  -- Scope: 1=System
        1033,  -- Language ID: 1033=English (US)
        '',  -- Company (empty = default company)
        1,  -- Debugger Break On Error: enabled
        0,  -- Debugger Break On Rec Changes: disabled
        1,  -- Debugger Skip System Triggers: enabled
        1033,  -- Locale ID: 1033=English (US)
        'UTC',  -- Time Zone: UTC (adjust if needed)
        0,  -- Customization Status: 0=None
        26027  -- Emit Version: 26027 for BC 26.0
    );
END

COMMIT TRANSACTION;

-- Verify user creation
SELECT
    [User Security ID] as UserGUID,
    [User Name] as Username,
    [Full Name] as FullName,
    [State] as State
FROM [dbo].[User]
WHERE [User Security ID] = '$USER_GUID';
"

# Execute SQL
RESULT=$(/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -d "$DATABASE" -C -N -Q "$SQL_SCRIPT" 2>&1)
SQL_EXIT_CODE=$?

if [ $SQL_EXIT_CODE -ne 0 ]; then
    log_error "SQL execution failed:"
    echo "$RESULT"
    exit 1
fi

log_success "User created successfully in database"

# Step 5: Verify user can be queried
log_info "Step 5/5: Verifying user creation..."

USER_CHECK=$(/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U sa -P "$SA_PASSWORD" -d "$DATABASE" -C -N -h -1 -Q "SET NOCOUNT ON; SELECT [User Name] FROM [dbo].[User] WHERE [User Security ID] = '$USER_GUID'" 2>/dev/null | tr -d '[:space:]')

if [ "$USER_CHECK" != "$USERNAME" ]; then
    log_error "User verification failed - user not found in database"
    exit 1
fi

log_success "User verified in database"

echo ""
log_success "═══════════════════════════════════════════════════════════════"
log_success "  User created successfully!"
log_success "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Username:        $USERNAME"
echo "  Password:        ***masked***"
echo "  User GUID:       $USER_GUID"
echo "  Permission Set:  $PERMISSION_SET"
echo "  State:           Enabled"
echo ""
log_info "Next steps:"
echo "  1. Test login via OData API:"
echo "     curl http://localhost:7048/BC/api/v2.0/companies \\"
echo "       -H \"Authorization: Basic \$(echo -n '$USERNAME:<password>' | base64)\""
echo ""
echo "  2. Restart BC Server to refresh cache (if login fails):"
echo "     docker restart bcdevonlinux-e036ace-bc-1"
echo ""
log_warn "Remember: This user was created outside official APIs."
log_warn "Monitor for any issues and be prepared to recreate via supported methods."
echo ""
