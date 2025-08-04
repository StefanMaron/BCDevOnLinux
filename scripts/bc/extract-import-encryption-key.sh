#!/bin/bash
# Extract and import BC encryption keys between environments

set -e

# Configuration
SOURCE_SERVER="${SOURCE_SERVER:-192.168.2.99}"
SOURCE_DB="${SOURCE_DB:-bc4ubuntu}"
TARGET_SERVER="${TARGET_SERVER:-sql}"
TARGET_DB="${TARGET_DB:-bc4ubuntu}"
SA_PASSWORD="${SA_PASSWORD:-P@ssw0rd123!}"

# Function to extract encryption key from source
extract_encryption_key() {
    echo "Extracting encryption key from source database..."
    
    # Create extraction script
    cat > /tmp/extract_key.sql << 'EOF'
-- Export public encryption key
SELECT 
    id,
    publickey,
    DATALENGTH(publickey) AS key_length
FROM [dbo].[$ndo$publicencryptionkey];
EOF

    # Execute extraction (adjust connection parameters as needed)
    /opt/mssql-tools18/bin/sqlcmd -S "$SOURCE_SERVER" -U sa -P "$SA_PASSWORD" -d "$SOURCE_DB" \
        -i /tmp/extract_key.sql -o encryption_key_data.txt -C
    
    echo "Encryption key extracted to encryption_key_data.txt"
}

# Function to import encryption key to target
import_encryption_key() {
    echo "Importing encryption key to target database..."
    
    # Parse the extracted data and create import script
    # Extract id and publickey from the output (skip header lines)
    ID=$(awk 'NR==3 {print $1}' encryption_key_data.txt)
    PUBLICKEY=$(awk 'NR==3 {print $2}' encryption_key_data.txt)
    
    cat > /tmp/import_key.sql << EOF
USE [$TARGET_DB];
GO

-- Ensure table exists
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '\$ndo\$publicencryptionkey')
BEGIN
    CREATE TABLE [dbo].[\$ndo\$publicencryptionkey] (
        [id] INT NOT NULL,
        [publickey] NVARCHAR(1024) NOT NULL,
        CONSTRAINT [PK_\$ndo\$publicencryptionkey] PRIMARY KEY CLUSTERED ([id])
    );
END
GO

-- Clear and insert new key
TRUNCATE TABLE [dbo].[\$ndo\$publicencryptionkey];
GO

INSERT INTO [dbo].[\$ndo\$publicencryptionkey] ([id], [publickey]) 
VALUES ($ID, N'$PUBLICKEY');
GO

-- Verify
SELECT id, DATALENGTH(publickey) AS key_length
FROM [dbo].[\$ndo\$publicencryptionkey];
GO
EOF

    # Execute import
    /opt/mssql-tools18/bin/sqlcmd -S "$TARGET_SERVER" -U sa -P "$SA_PASSWORD" \
        -i /tmp/import_key.sql -C
    
    echo "Encryption key imported successfully"
}

# Function to export as INSERT statement (alternative method)
export_key_insert() {
    echo "Exporting encryption key as INSERT statement..."
    
    cat > /tmp/export_insert.sql << 'EOF'
-- Generate INSERT statement
SELECT 
    'INSERT INTO [dbo].[$ndo$publicencryptionkey] (id, publickey) VALUES (' +
    CAST(id AS VARCHAR(10)) + ', ' +
    'N''' + publickey + ''');' AS InsertStatement
FROM [dbo].[$ndo$publicencryptionkey];
EOF

    /opt/mssql-tools18/bin/sqlcmd -S "$SOURCE_SERVER" -U sa -P "$SA_PASSWORD" -d "$SOURCE_DB" \
        -i /tmp/export_insert.sql -o encryption_key_insert.txt -C -y 0 -Y 0
    
    echo "INSERT statement saved to encryption_key_insert.txt"
}

# Main script logic
case "${1:-extract}" in
    extract)
        extract_encryption_key
        ;;
    import)
        import_encryption_key
        ;;
    insert)
        export_key_insert
        ;;
    full)
        extract_encryption_key
        import_encryption_key
        ;;
    *)
        echo "Usage: $0 {extract|import|base64|full}"
        echo "  extract - Extract key from source database"
        echo "  import  - Import key to target database"
        echo "  insert  - Export key as INSERT statement"
        echo "  full    - Extract from source and import to target"
        exit 1
        ;;
esac
