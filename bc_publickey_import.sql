-- Import BC public encryption key
USE [BC];
GO

-- Create table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '$ndo$publicencryptionkey')
BEGIN
    CREATE TABLE [dbo].[$ndo$publicencryptionkey] (
        [id] INT NOT NULL,
        [publickey] NVARCHAR(1024) NOT NULL,
        CONSTRAINT [PK_$ndo$publicencryptionkey] PRIMARY KEY CLUSTERED ([id])
    );
END
GO

-- Clear existing keys
TRUNCATE TABLE [dbo].[$ndo$publicencryptionkey];
GO

-- Insert will be appended below
INSERT INTO [dbo].[$ndo$publicencryptionkey] (id, publickey) VALUES (0, N'<RSAKeyValue><Modulus>rjZm9wnw6o2l+vdPhy/Find9c4xHkxXaoxf5cO6xmJKk9vb3ygFejQIEhcFx0/J/4mROhqh2wypkB1FV6bUSuFvCs02sdM9MRNvEQQyLklYiP5FqGfKIqiojw1lqkxz/SQKm5gyrRUJjoD7qE7kLuQVeR8xE4EaEGC0mY/hdbIh6BJVLy++A53enTvq14jV+JutLethY23E56wlHs2zDMrlQ6hwovmAJSZkS+A7DRg0QwBYWfYFZMIb8uxqtjS8kwTBnPXAk5QBnqUoltou3TnBJ7lyRF269jfPK+Czf9YJ03iS6qyjcI8dW/6wswlGBBdnmX/2P6Ksykde0ck51lQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>');
