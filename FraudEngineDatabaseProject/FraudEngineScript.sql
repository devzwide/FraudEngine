/*
    FraudEngine schema + seed script
    - Creates Customers, Accounts, Transactions, Rules, FraudAlerts
    - Adds a stored procedure `usp_EvaluateTransaction` that creates alerts
    - Inserts sample seed data for quick testing
*/

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dbo')
    EXEC('CREATE SCHEMA dbo');

-- Customers
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Customers' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.Customers
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        FullName NVARCHAR(200) NOT NULL,
        Email NVARCHAR(320) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END

-- Accounts
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Accounts' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.Accounts
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        CustomerId INT NOT NULL REFERENCES dbo.Customers(Id),
        AccountNumber NVARCHAR(50) NOT NULL UNIQUE,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END

-- Transactions
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Transactions' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.Transactions
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        AccountId INT NOT NULL REFERENCES dbo.Accounts(Id),
        Amount DECIMAL(18,2) NOT NULL,
        Currency NVARCHAR(10) NOT NULL DEFAULT 'USD',
        TransactionTime DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        Merchant NVARCHAR(200) NULL,
        Location NVARCHAR(200) NULL,
        IsFlagged BIT NOT NULL DEFAULT 0
    );
END

-- Rules (simple rule store)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Rules' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.Rules
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(200) NOT NULL UNIQUE,
        Description NVARCHAR(1000) NULL,
        NumericThreshold DECIMAL(18,2) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END

-- Fraud alerts
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FraudAlerts' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.FraudAlerts
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        TransactionId INT NOT NULL REFERENCES dbo.Transactions(Id),
        AlertType NVARCHAR(200) NOT NULL,
        Score DECIMAL(5,2) NOT NULL DEFAULT 0,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END

GO

-- Stored procedure: evaluate a transaction against simple rules
IF OBJECT_ID('dbo.usp_EvaluateTransaction', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EvaluateTransaction;
GO
CREATE PROCEDURE dbo.usp_EvaluateTransaction
    @TransactionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Amount DECIMAL(18,2);
    SELECT @Amount = Amount FROM dbo.Transactions WHERE Id = @TransactionId;

    IF @Amount IS NULL
    BEGIN
        RAISERROR('Transaction not found: %d', 16, 1, @TransactionId);
        RETURN;
    END

    -- Simple rule: compare to rule named 'AmountThreshold'
    DECLARE @Threshold DECIMAL(18,2);
    SELECT TOP(1) @Threshold = NumericThreshold FROM dbo.Rules WHERE Name = 'AmountThreshold';

    IF @Threshold IS NULL
        SET @Threshold = 10000.00; -- default fallback

    IF @Amount >= @Threshold
    BEGIN
        INSERT INTO dbo.FraudAlerts (TransactionId, AlertType, Score)
        VALUES (@TransactionId, 'HighAmount', 100.00);

        UPDATE dbo.Transactions SET IsFlagged = 1 WHERE Id = @TransactionId;
    END
END
GO

-- Seed data (idempotent)
IF NOT EXISTS (SELECT 1 FROM dbo.Customers)
BEGIN
    INSERT INTO dbo.Customers (FullName, Email)
    VALUES
        ('Alice Johnson', 'alice@example.com'),
        ('Bob Martinez', 'bob@example.com'),
        ('Carol Lee', 'carol@example.com');

    INSERT INTO dbo.Accounts (CustomerId, AccountNumber)
    SELECT Id, CONCAT('ACCT-', RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY Id) AS VARCHAR(6)),6))
    FROM dbo.Customers;

    -- Add a rule
    INSERT INTO dbo.Rules (Name, Description, NumericThreshold)
    VALUES ('AmountThreshold', 'Flag transactions with large amounts', 5000.00);

    -- Add sample transactions
    DECLARE @acct1 INT = (SELECT TOP 1 Id FROM dbo.Accounts ORDER BY Id);
    DECLARE @acct2 INT = (SELECT TOP 1 Id FROM dbo.Accounts ORDER BY Id DESC);

    INSERT INTO dbo.Transactions (AccountId, Amount, Currency, Merchant, Location, TransactionTime)
    VALUES
        (@acct1, 12.50, 'USD', 'Coffee Shop', 'Seattle, WA', DATEADD(HOUR, -5, SYSUTCDATETIME())),
        (@acct1, 120000.00, 'USD', 'Luxury Cars Inc', 'Los Angeles, CA', DATEADD(DAY, -1, SYSUTCDATETIME())),
        (@acct2, 42.00, 'USD', 'Bookstore', 'Portland, OR', DATEADD(HOUR, -2, SYSUTCDATETIME()));

    -- Evaluate transactions to create alerts where appropriate
    DECLARE @tId INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM dbo.Transactions;
    OPEN cur; FETCH NEXT FROM cur INTO @tId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.usp_EvaluateTransaction @tId;
        FETCH NEXT FROM cur INTO @tId;
    END
    CLOSE cur; DEALLOCATE cur;
END

GO

SET NOCOUNT OFF;