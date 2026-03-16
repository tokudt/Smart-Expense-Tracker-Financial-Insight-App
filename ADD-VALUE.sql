USE DATA_expense;

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'DATA_expense')
BEGIN
    CREATE DATABASE DATA_expense;
    USE DATA_expense;
END
GO

INSERT INTO dbo.users (username, email)
VALUES ('Dat Pham', 'dat@example.com');
GO

INSERT INTO dbo.accounts (user_id, account_type, institution, balance)
VALUES 
(1, 'Bank', 'Vietcombank', 15000000),
(1, 'Cash', 'Vietcombank', 2000000),
(1, 'Ewallet', 'Momo', 1000000);

INSERT INTO categories (user_id, parent_id, name, expense_type, is_system) VALUES
(NULL, NULL, 'Housing',           'fixed',        1),
(NULL, NULL, 'Food & Dining',     'variable',     1),
(NULL, NULL, 'Transport',         'semi_variable', 1),
(NULL, NULL, 'Health',            'variable',     1),
(NULL, NULL, 'Entertainment',     'variable',     1),
(NULL, NULL, 'Shopping',          'variable',     1),
(NULL, NULL, 'Utilities',         'semi_variable', 1),
(NULL, NULL, 'Education',         'fixed',        1),
(NULL, NULL, 'Personal Care',     'variable',     1),
(NULL, NULL, 'Savings',           'fixed',        1),
(NULL, NULL, 'Income',            'variable',     1);

-- Expense categories
INSERT INTO dbo.categories (name, expense_type)
VALUES
('Food', 'Expense'),
('Transportation', 'Expense'),
('Entertainment', 'Expense'),
('Utilities', 'Expense'),
('Shopping', 'Expense');

-- Income categories
INSERT INTO dbo.categories (name, expense_type)
VALUES
('Salary', 'Income'),
('Freelance', 'Income');

INSERT INTO dbo.transactions 
(user_id, account_id, category_id, amount, transaction_type, description, transaction_date)
VALUES
(1, 1, 6, 25000000, 'Income', 'Monthly Salary', GETDATE()),
(1, 1, 1, 500000, 'Expense', 'Groceries', GETDATE()),
(1, 2, 2, 200000, 'Expense', 'Grab ride', GETDATE()),
(1, 3, 3, 150000, 'Expense', 'Netflix subscription', GETDATE());

INSERT INTO dbo.budgets (user_id, budget_id, budget_amount, period_type, period_start, period_end)
VALUES
(1, 1, 3000000, 'MONTHLY', '2026-02-01', '2026-02-28'),
(1, 2, 1000000, 'MONTHLY', '2026-02-01', '2026-02-28');
