#!/bin/bash
# Import BC encryption key into database

set -e

# Configuration
SQL_SERVER="${SQL_SERVER:-sql}"
# Try to get database name from CustomSettings.config if not set
if [ -z "$DATABASE_NAME" ] && [ -f "/home/CustomSettings.config" ]; then
    DATABASE_NAME=$(grep -oP '(?<=DatabaseName" value=")[^"]+' /home/CustomSettings.config 2>/dev/null || echo "")
fi
DATABASE_NAME="${DATABASE_NAME:-CRONUS}"
SA_PASSWORD="${SA_PASSWORD:-P@ssw0rd123!}"

echo "Importing encryption key into $DATABASE_NAME database..."

# The RSA public key from encryption_key_data.txt
PUBLICKEY='<RSAKeyValue><Modulus>rjZm9wnw6o2l+vdPhy/Find9c4xHkxXaoxf5cO6xmJKk9vb3ygFejQIEhcFx0/J/4mROhqh2wypkB1FV6bUSuFvCs02sdM9MRNvEQQyLklYiP5FqGfKIqiojw1lqkxz/SQKm5gyrRUJjoD7qE7kLuQVeR8xE4EaEGC0mY/hdbIh6BJVLy++A53enTvq14jV+JutLethY23E56wlHs2zDMrlQ6hwovmAJSZkS+A7DRg0QwBYWfYFZMIb8uxqtjS8kwTBnPXAk5QBnqUoltou3TnBJ7lyRF269jfPK+Czf9YJ03iS6qyjcI8dW/6wswlGBBdnmX/2P6Ksykde0ck51lQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'

# Create SQL script
cat > /tmp/import_encryption_key.sql << EOF
USE [$DATABASE_NAME];
GO

-- Create table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '\$ndo\$publicencryptionkey')
BEGIN
    CREATE TABLE [dbo].[\$ndo\$publicencryptionkey] (
        [id] INT NOT NULL,
        [publickey] NVARCHAR(1024) NOT NULL,
        CONSTRAINT [PK_\$ndo\$publicencryptionkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'Created table [\$ndo\$publicencryptionkey]'
END
ELSE
BEGIN
    PRINT 'Table [\$ndo\$publicencryptionkey] already exists'
END
GO

-- Clear existing keys
DELETE FROM [dbo].[\$ndo\$publicencryptionkey];
GO

-- Insert the RSA public key
INSERT INTO [dbo].[\$ndo\$publicencryptionkey] ([id], [publickey]) 
VALUES (0, N'$PUBLICKEY');
GO

-- Verify the import
SELECT 
    id,
    CASE 
        WHEN publickey IS NOT NULL THEN 'Key imported successfully'
        ELSE 'Key import failed'
    END AS status,
    DATALENGTH(publickey) AS key_length
FROM [dbo].[\$ndo\$publicencryptionkey];
GO
EOF

# Execute the import
/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER" -U sa -P "$SA_PASSWORD" \
    -i /tmp/import_encryption_key.sql -C

echo "Encryption key import completed!"

# Clean up
rm -f /tmp/import_encryption_key.sql