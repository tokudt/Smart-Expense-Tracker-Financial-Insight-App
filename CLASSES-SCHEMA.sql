
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'DATA_expense')
BEGIN
    CREATE DATABASE DATA_expense;
END
GO

USE DATA_expense;
GO
-- ============================================================
--  PERSONAL FINANCE DATABASE
--  Supports: Expense Analysis, Behavior & Insights,
--            Financial Health & Predictive Analytics
-- ============================================================


-- ============================================================
-- SECTION 1: CORE REFERENCE TABLES
-- ============================================================


CREATE TABLE dbo.users (
	user_id		INT PRIMARY KEY,
	username	NVARCHAR(100) NOT NULL UNIQUE,
	email		NVARCHAR(255)NOT NULL UNIQUE,
	currency	CHAR(5) NOT NULL DEFAULT 'USD',
	created_at 	DATETIME2 DEFAULT SYSDATETIME(),
	updated_at 	DATETIME2 DEFAULT SYSDATETIME(),
	row_version ROWVERSION
);
-- ──────────────────────────────────────────────────────────
-- Categories: hierarchical (parent → child)
-- expense_type: FIXED | VARIABLE | SEMI_VARIABLE
-- ──────────────────────────────────────────────────────────

CREATE TABLE dbo.categories (
	category_id INT IDENTITY(1,1) PRIMARY KEY,
	user_id		INT REFERENCES dbo.users(user_id) ON DELETE CASCADE,
	parent_id	INT NULL REFERENCES dbo.categories(category_id),
	name 		NVARCHAR(100) NOT NULL,
	icon		NVARCHAR(255) NULL,
	color		NVARCHAR(7) NULL, -- HEX color code
	expense_type NVARCHAR(20) NOT NULL DEFAULT 'variable'
					CHECK (expense_type IN ('fixed', 'variable', 'semi_variable')),
	is_system   BIT NOT NULL DEFAULT 0,   -- built-in vs user-defined use BIT for boolean)

	created_at DATETIME2 DEFAULT SYSDATETIME(),
	updated_at DATETIME2 DEFAULT SYSDATETIME()
);
-- Seed: system-level categories
INSERT INTO dbo.categories (user_id, parent_id, name, expense_type, is_system) VALUES
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

CREATE TABLE dbo.accounts (
	account_id	INT PRIMARY KEY,
	user_id		INT NOT NULL REFERENCES dbo.users(user_id),
	name		NVARCHAR(100) NOT NULL,
	account_type NVARCHAR(30) NOT NULL
					CHECK (account_type IN ('CHECKING', 'SAVING', 'CREDIT_CARD', 'CASH', 'INVESTMENT', 'LOAN')),
	balance		DECIMAL(14,2) NOT NULL DEFAULT 0,
	credit_limit DECIMAL(14,2),
	currency	CHAR(5) NOT NULL DEFAULT 'DONG',
	institution	NVARCHAR(100),
	is_active	BIT NOT NULL DEFAULT 1,
	created_at	DATETIME NOT NULL DEFAULT GETDATE()
);

-- ──────────────────────────────────────────────────────────
-- Tags: flexible labeling (e.g. "business", "recurring")
-- ──────────────────────────────────────────────────────────


CREATE TABLE tags (
	tags_id		INT PRIMARY KEY,
	user_id		INT NOT NULL REFERENCES dbo.users(user_id),
	name		NVARCHAR(50) NOT NULL,
	UNIQUE (user_id, name)
);

-- ============================================================
-- SECTION 2: TRANSACTIONS
-- ============================================================


CREATE TABLE transactions (
	transaction_id INT PRIMARY KEY,
	user_id			INT NOT NULL REFERENCES dbo.users(user_id),
	account_id		INT NOT NULL REFERENCES dbo.accounts(account_id),
	category_id		INT REFERENCES dbo.categories(category_id),

	-- Core amounts
	amount			NUMERIC(14,2) NOT NULL CHECK (amount > 0),
	currency		CHAR(3) NOT NULL DEFAULT 'DONG',
	amount_base_currency NUMERIC(14,2),
	exchange_rate	NUMERIC(12,6) DEFAULT 1.0,

	-- Direction & type
	transaction_type NVARCHAR(20) NOT NULL
				CHECK (transaction_type IN ('EXPENSE', 'INCOME', 'TRANSFER', 'REFUND', 'INVESTMENT')),
	is_recurring	BIT NOT NULL DEFAULT 1,
	recurrence_id	INT,

	-- Metadata
	merchant		NVARCHAR(255),
	description		NTEXT,
	notes			NTEXT,
	transaction_date DATE NOT NULL,
	posted_date		DATE,

	-- Location (optional, for geo-analytics)
	latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    city                NVARCHAR(100),
    country             CHAR(2),

	-- Flags 
    is_verified         BIT NOT NULL DEFAULT 0,
    is_excluded         BIT NOT NULL DEFAULT 0, -- exclude from analytics
    created_at 			DATETIME2 DEFAULT SYSDATETIME(),
	updated_at 			DATETIME2 DEFAULT SYSDATETIME(),
	row_version 		ROWVERSION
);

-- Many-to-many: transactions ↔ tags
CREATE TABLE transaction_tags (
	transaction_id 		INT NOT NULL REFERENCES dbo.transactions(transaction_id) ON DELETE CASCADE,
	tags_id				INT NOT NULL REFERENCES dbo.tags(tags_id) ON DELETE CASCADE,
	PRIMARY KEY (transaction_id, tags_id)
);

-- ──────────────────────────────────────────────────────────
-- Recurring rules (subscriptions, rent, salary, etc.)
-- ──────────────────────────────────────────────────────────

CREATE TABLE recurring_rules (
	recurrence_id 		INT PRIMARY KEY,
	user_id				INT NOT NULL REFERENCES dbo.users(user_id),
	account_id			INT NOT NULL REFERENCES dbo.accounts(account_id),
	category_id			INT REFERENCES dbo.categories(category_id),
	amount				DECIMAL(14,2) NOT NULL CHECK (amount > 0),
	description 		NVARCHAR(255),
	frequency 			NVARCHAR(20) NOT NULL
							CHECK (frequency IN ('DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY', 'QUARTERLY', 'ANNUALLY')),
	start_date 			DATE NOT NULL,
	end_date 			DATE,
	last_generated_date DATE,
	is_active 			BIT NOT NULL DEFAULT 1,
	created_at 			DATETIME2 DEFAULT SYSDATETIME()
);

-- Back-fill FK
ALTER TABLE transactions
    ADD CONSTRAINT fk_recurrence
    FOREIGN KEY (recurrence_id)
    REFERENCES recurring_rules(recurrence_id);

-- ============================================================
-- SECTION 3: BUDGETS
-- ============================================================

CREATE TABLE budgets (
	budget_id		INT PRIMARY KEY,
	user_id			INT NOT NULL REFERENCES dbo.users(user_id),
	name			NVARCHAR(100) NOT NULL,
	
	-- Period
    period_type     NVARCHAR(10) NOT NULL DEFAULT 'MONTHLY'
                        CHECK (period_type IN ('WEEKLY','MONTHLY','QUARTERLY','YEARLY','CUSTOM')),
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,


	-- Amount & thresholds
	budget_amount	DECIMAL(14,2) NOT NULL CHECK (budget_amount > 0),
	rollover        BIT NOT NULL DEFAULT 0, -- rollover unused budget	
	alert_threshold DECIMAL (5,2) NOT NULL DEFAULT 80.00 CHECK (alert_threshold > 0 AND alert_threshold <= 100), -- percentage

	is_active		BIT NOT NULL DEFAULT 1,
	created_at		DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

-- ============================================================
-- SECTION 4: ANALYTICS SUPPORT TABLES
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Daily aggregates — pre-computed for speed
-- (populated by trigger or scheduled job)
-- ──────────────────────────────────────────────────────────

CREATE TABLE daily_summaries (
	summary_id		INT PRIMARY KEY,
	user_id			INT NOT NULL REFERENCES dbo.users(user_id),
	summary_date	DATE NOT NULL,
	total_expense	DECIMAL(14,2) NOT NULL DEFAULT 0,
	total_income	DECIMAL(14,2) NOT NULL DEFAULT 0,
	net_amount		DECIMAL(14,2) NOT NULL DEFAULT 0,
	created_at		DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
	UNIQUE (user_id, summary_date)
);


-- ──────────────────────────────────────────────────────────
-- Monthly category totals — for trend & anomaly queries
-- ──────────────────────────────────────────────────────────

CREATE TABLE monthly_category_totals (
	mc_total_id	INT PRIMARY KEY,
	user_id		INT NOT NULL REFERENCES dbo.users(user_id),
	category_id	INT NOT NULL REFERENCES dbo.categories(category_id),
	year		SMALLINT NOT NULL,
	month		SMALLINT NOT NULL CHECK (month >= 1 AND month <= 12),
	total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
	transaction_count INT NOT NULL DEFAULT 0,
	avg_transaction DECIMAL(14,2),
	UNIQUE (user_id, category_id, year, month)
);

-- ──────────────────────────────────────────────────────────
-- Spending scores & health snapshots
-- (one row per user per month)
-- ──────────────────────────────────────────────────────────

CREATE TABLE financial_snapshots (
    snapshot_id             INT PRIMARY KEY,
    user_id                 INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    year                    SMALLINT NOT NULL,
    month                   SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),

    -- Expense Analysis
    total_expenses          DECIMAL(14,2),
    total_income            DECIMAL(14,2),
    net_savings             DECIMAL(14,2),
    savings_rate_pct        DECIMAL(6,3),             -- net_savings / income * 100
    fixed_expense_total     DECIMAL(14,2),
    variable_expense_total  DECIMAL(14,2),

    -- Behavior & Insight
    budget_adherence_pct    DECIMAL(6,3),             -- % of budgets not exceeded
    overspent_categories    NVARCHAR(MAX),                     -- [{category, budgeted, actual}]
    anomaly_flags           NVARCHAR(MAX),                     -- [{category, score, reason}]
    spending_consistency_score DECIMAL(5,2),          -- 0–100

    -- Financial Health
    burn_rate               DECIMAL(14,2),             -- avg daily expense
    predicted_next_month    DECIMAL(14,2),             -- model output
    months_of_runway        DECIMAL(6,2),              -- savings / burn_rate

    computed_at             DATETIME2 DEFAULT SYSDATETIME(),
    UNIQUE (user_id, year, month)
);

-- ──────────────────────────────────────────────────────────
-- Anomaly log — detected individually
-- ──────────────────────────────────────────────────────────
CREATE TABLE anomalies (
    anomaly_id          INT PRIMARY KEY,
    user_id             INT NOT NULL REFERENCES dbo.users(user_id) ON DELETE CASCADE,
    transaction_id      INT REFERENCES dbo.transactions(transaction_id),
    category_id         INT REFERENCES dbo.categories(category_id),
    anomaly_type        NVARCHAR(50) NOT NULL
                            CHECK (anomaly_type IN (
                                'OVERSPEND','UNUSUAL_MERCHANT','LARGE_TRANSACTION',
                                'FREQUENCY_SPIKE','CATEGORY_GROWTH','BUDGET_BREACH'
                            )),
    severity            NVARCHAR(10) NOT NULL DEFAULT 'MEDIUM'
                            CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    description         TEXT,
    detected_at         DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    acknowledged_at     DATETIME2,
    is_false_positive   BIT NOT NULL DEFAULT 0
);


-- ============================================================
-- SECTION 5: INDEXES FOR ANALYTICS PERFORMANCE
-- ============================================================

-- Hot path: all user expenses in a date range
CREATE INDEX idx_txn_user_date
    ON transactions (user_id, transaction_date DESC);

-- Category drill-down
CREATE INDEX idx_txn_user_category
    ON transactions (user_id, category_id, transaction_date DESC);

-- Monthly category roll-ups
CREATE INDEX idx_mct_user_period
    ON monthly_category_totals (user_id, year DESC, month DESC);

-- Anomaly lookups
CREATE INDEX idx_anomaly_user
    ON anomalies (user_id, detected_at DESC);

-- Recurring transactions
CREATE INDEX idx_txn_recurrence
    ON transactions (recurrence_id)
    WHERE recurrence_id IS NOT NULL;

-- Budget period lookup
CREATE INDEX idx_budget_user_period
	ON budgets (user_id, period_start, period_end);

GO

CREATE TRIGGER trg_update_dp_users_updated_at
ON dbo.users
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE dbo.users
	SET updated_at = SYSUTCDATETIME()
	FROM inserted i
	WHERE dbo.users.user_id = i.user_id;
END;



-- ============================================================
-- SECTION 6: VIEWS (pre-built insight queries)
-- ============================================================

-- ── WHERE IS MONEY GOING? (current month) ──────────────────
DROP VIEW IF EXISTS vw_current_month_by_category;
GO

CREATE VIEW vw_current_month_by_category AS
SELECT
    t.user_id,
    c.name                              AS category,
    c.expense_type,
    SUM(t.amount)                       AS total_spent,
    COUNT(*)                            AS txn_count,
    ROUND(AVG(t.amount), 2)             AS avg_per_txn
FROM transactions t
JOIN categories c ON c.category_id = t.category_id
WHERE t.transaction_type = 'EXPENSE'
  AND t.is_excluded = 0
  AND DATEPART(YEAR, t.transaction_date) = DATEPART(YEAR, GETDATE())
  AND DATEPART(MONTH, t.transaction_date) = DATEPART(MONTH, GETDATE())
GROUP BY t.user_id, c.name, c.expense_type;
GO

-- ── CATEGORY GROWTH (MoM %) ────────────────────────────────
DROP VIEW IF EXISTS vw_category_growth_mom;
GO

CREATE VIEW vw_category_growth_mom AS
SELECT
    cur.user_id,
    cur.category_id,
    c.name                                          AS category,
    cur.year,
    cur.month,
    cur.total_amount                                AS current_amount,
    prev.total_amount                               AS prev_amount,
    CASE WHEN prev.total_amount > 0
         THEN ROUND(((cur.total_amount - prev.total_amount)
                     / prev.total_amount) * 100, 2)
         ELSE NULL
    END                                             AS growth_pct
FROM monthly_category_totals cur
LEFT JOIN monthly_category_totals prev
       ON prev.user_id     = cur.user_id
      AND prev.category_id = cur.category_id
      AND (prev.year * 12 + prev.month) = (cur.year * 12 + cur.month) - 1
JOIN categories c ON c.category_id = cur.category_id;
GO

-- ── FIXED vs VARIABLE SPLIT ────────────────────────────────
DROP VIEW IF EXISTS vw_fixed_variable_split;
GO

CREATE VIEW vw_fixed_variable_split AS
SELECT
    t.user_id,
    DATEFROMPARTS(YEAR(t.transaction_date), MONTH(t.transaction_date), 1) AS month,
    SUM(CASE WHEN c.expense_type = 'FIXED'    THEN t.amount ELSE 0 END) AS fixed_total,
    SUM(CASE WHEN c.expense_type = 'VARIABLE' THEN t.amount ELSE 0 END) AS variable_total,
    SUM(CASE WHEN c.expense_type = 'SEMI_VARIABLE' THEN t.amount ELSE 0 END) AS semi_variable_total,
    SUM(t.amount) AS grand_total
FROM transactions t
JOIN categories c ON c.category_id = t.category_id
WHERE t.transaction_type = 'EXPENSE'
  AND t.is_excluded = 0
GROUP BY t.user_id, DATEFROMPARTS(YEAR(t.transaction_date), MONTH(t.transaction_date), 1);
GO

-- ── BUDGET ADHERENCE ───────────────────────────────────────
DROP VIEW IF EXISTS vw_budget_adherence;
GO

CREATE VIEW vw_budget_adherence AS
SELECT
    b.user_id,
    b.budget_id,
    b.name AS budget_name,
    NULL AS category,
    b.budget_amount,
    COALESCE(SUM(t.amount),0) AS spent_amount,
    b.budget_amount - COALESCE(SUM(t.amount),0) AS remaining,
    ROUND(COALESCE(SUM(t.amount),0) / NULLIF(b.budget_amount,0) * 100,2) AS pct_used,
    CASE 
        WHEN COALESCE(SUM(t.amount),0) > b.budget_amount THEN 1 
        ELSE 0 
    END AS is_overspent
FROM budgets b
LEFT JOIN transactions t
    ON t.user_id = b.user_id
    AND t.transaction_date BETWEEN b.period_start AND b.period_end
    AND t.transaction_type = 'EXPENSE'
    AND t.is_excluded = 0
WHERE b.is_active = 1
GROUP BY b.user_id, b.budget_id, b.name, b.budget_amount;
GO

-- ── DAILY SPENDING TREND (last 90 days) ────────────────────
DROP VIEW IF EXISTS vw_daily_spending_trend;
GO

CREATE VIEW vw_daily_spending_trend AS
SELECT
    user_id,
    summary_date,
    total_expense,
    total_income,
    net_amount,

    AVG(total_expense) OVER (
        PARTITION BY user_id
        ORDER BY summary_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_avg,

    AVG(total_expense) OVER (
        PARTITION BY user_id
        ORDER BY summary_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30d_avg

FROM daily_summaries
WHERE summary_date >= DATEADD(DAY,-90,GETDATE());
GO

-- ── SAVINGS RATE ───────────────────────────────────────────
DROP VIEW IF EXISTS vw_savings_rate;
GO

CREATE VIEW vw_savings_rate AS
SELECT
    user_id,
    year,
    month,
    total_income,
    total_expenses,
    net_savings,
    savings_rate_pct,
    burn_rate,
    months_of_runway,
    predicted_next_month
FROM financial_snapshots;
GO

-- ============================================================
-- SECTION 7: HELPER FUNCTIONS
-- ============================================================

-- Refresh daily summary for a user on a given date
CREATE OR ALTER PROCEDURE refresh_daily_summary
    @p_user_id INT,
    @p_date    DATE
AS
BEGIN
MERGE daily_summaries AS target
USING (
    SELECT
        @p_user_id AS user_id,
        @p_date AS summary_date,
        SUM(CASE WHEN transaction_type='EXPENSE' THEN amount ELSE 0 END) AS total_expense,
        SUM(CASE WHEN transaction_type='INCOME' THEN amount ELSE 0 END) AS total_income
    FROM transactions
    WHERE user_id=@p_user_id
      AND transaction_date=@p_date
      AND is_excluded=0
) AS src
ON target.user_id = src.user_id
AND target.summary_date = src.summary_date

WHEN MATCHED THEN
UPDATE SET
    total_expense = src.total_expense,
    total_income = src.total_income

WHEN NOT MATCHED THEN
INSERT (user_id,summary_date,total_expense,total_income,net_amount)
VALUES (
    src.user_id,
    src.summary_date,
    src.total_expense,
    src.total_income,
    src.total_income - src.total_expense
);

END
GO


-- Auto-trigger: refresh daily summary whenever a transaction is inserted/updated
CREATE OR ALTER TRIGGER after_transaction_upsert
ON transactions
AFTER INSERT, UPDATE
AS
BEGIN

DECLARE @user_id INT
DECLARE @date DATE

SELECT TOP 1
    @user_id = user_id,
    @date = transaction_date
FROM inserted

EXEC refresh_daily_summary @user_id, @date

END
GO



-- Compute spending consistency score (0-100)
-- Higher = more consistent day-to-day spending
CREATE OR ALTER FUNCTION compute_consistency_score(
    @p_user_id   INT,
    @p_year      SMALLINT,
    @p_month     SMALLINT
) 

RETURNS DECIMAL(5,2)
AS
BEGIN

DECLARE @stddev FLOAT
DECLARE @mean FLOAT
DECLARE @cv FLOAT
DECLARE @score FLOAT

SELECT
    @stddev = STDEV(total_expense),
    @mean = AVG(total_expense)
FROM daily_summaries
WHERE user_id=@p_user_id
AND YEAR(summary_date)=@p_year
AND MONTH(summary_date)=@p_month

IF @mean IS NULL OR @mean=0
RETURN NULL

SET @cv = @stddev/@mean
SET @score = 100*(1-IIF(@cv>1,1,@cv))

RETURN ROUND(@score,2)

END
GO

