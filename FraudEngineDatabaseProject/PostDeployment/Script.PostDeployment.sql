/*
  Post-Deployment Script
  This script is executed after DACPAC deployment. It contains idempotent seed data.
*/

SET NOCOUNT ON;
GO

-- Seed data (idempotent)
IF NOT EXISTS (SELECT 1 FROM [dbo].[Customers])
BEGIN
    INSERT INTO [dbo].[Customers] ([FullName], [Email])
    VALUES
        ('Alice Johnson', 'alice@example.com'),
        ('Bob Martinez', 'bob@example.com'),
        ('Carol Lee', 'carol@example.com');

    INSERT INTO [dbo].[Accounts] ([CustomerId], [AccountNumber])
    SELECT [Id], CONCAT('ACCT-', RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY [Id]) AS VARCHAR(6)),6))
    FROM [dbo].[Customers];

    -- Add a rule
    INSERT INTO [dbo].[Rules] ([Name], [Description], [NumericThreshold])
    VALUES ('AmountThreshold', 'Flag transactions with large amounts', 5000.00);

    -- Add sample transactions
    DECLARE @acct1 INT = (SELECT TOP 1 [Id] FROM [dbo].[Accounts] ORDER BY [Id]);
    DECLARE @acct2 INT = (SELECT TOP 1 [Id] FROM [dbo].[Accounts] ORDER BY [Id] DESC);

    INSERT INTO [dbo].[Transactions] ([AccountId], [Amount], [Currency], [Merchant], [Location], [TransactionTime])
    VALUES
        (@acct1, 12.50, 'USD', 'Coffee Shop', 'Seattle, WA', DATEADD(HOUR, -5, SYSUTCDATETIME())),
        (@acct1, 120000.00, 'USD', 'Luxury Cars Inc', 'Los Angeles, CA', DATEADD(DAY, -1, SYSUTCDATETIME())),
        (@acct2, 42.00, 'USD', 'Bookstore', 'Portland, OR', DATEADD(HOUR, -2, SYSUTCDATETIME()));

    -- Evaluate transactions to create alerts where appropriate
    DECLARE @tId INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT [Id] FROM [dbo].[Transactions];
    OPEN cur; FETCH NEXT FROM cur INTO @tId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [dbo].[usp_EvaluateTransaction] @tId;
        FETCH NEXT FROM cur INTO @tId;
    END
    CLOSE cur; DEALLOCATE cur;
END
GO
