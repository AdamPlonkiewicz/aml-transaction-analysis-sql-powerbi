-- =====================================================
-- 99_reporting_views.sql
-- Widoki raportowe dla Power BI.
--
-- vw_fact_transactions - tabela faktów: wszystkie transakcje,
--   przedziały kwot oraz flagi trzech reguł (pliki 04-06).
-- vw_sample_accounts   - transakcje 6 przykładowych kont (plik 07)
--   do osi czasu w raporcie.
-- =====================================================


DROP VIEW IF EXISTS vw_fact_transactions;

CREATE VIEW vw_fact_transactions AS
SELECT
    atc.transaction_id,
    atc.sender_id,
    atc.receiver_id, 
    atc.transaction_datetime::date AS transaction_date,
    EXTRACT(HOUR FROM atc.transaction_datetime)::int AS transaction_hour,
    atc.amount,
    atc.payment_type,
    atc.payment_currency,
    atc.received_currency,
    atc.sender_bank_location,
    atc.receiver_bank_location,
    atc.is_laundering,
    atc.laundering_type,
    CASE
        WHEN atc.amount < 100    THEN '< 100'
        WHEN atc.amount < 500    THEN '100-499'
        WHEN atc.amount < 1000   THEN '500-999'
        WHEN atc.amount < 5000   THEN '1k-4.9k'
        WHEN atc.amount < 10000  THEN '5k-9.9k'
        WHEN atc.amount < 50000  THEN '10k-49.9k'
        ELSE                      '50k+'
    END AS amount_range,
    CASE
        WHEN atc.amount < 100    THEN 1
        WHEN atc.amount < 500    THEN 2
        WHEN atc.amount < 1000   THEN 3
        WHEN atc.amount < 5000   THEN 4
        WHEN atc.amount < 10000  THEN 5
        WHEN atc.amount < 50000  THEN 6
        ELSE                      7
    END AS amount_range_order,
    CASE WHEN str.transaction_id IS NOT NULL THEN 1 ELSE 0 END AS flag_structuring,
    CASE WHEN smu.transaction_id IS NOT NULL THEN 1 ELSE 0 END AS flag_smurfing,
    CASE WHEN cw.transaction_id IS NOT NULL THEN 1 ELSE 0 END AS flag_cash_withdrawal
FROM aml_transactions_clean atc
LEFT JOIN flags_structuring str ON atc.transaction_id = str.transaction_id
LEFT JOIN flags_smurfing smu ON atc.transaction_id = smu.transaction_id
LEFT JOIN flags_cash_withdrawal cw ON atc.transaction_id = cw.transaction_id;

SELECT
    COUNT(*)                  AS total_rows,
    SUM(flag_structuring)     AS flagged_structuring,
    SUM(flag_smurfing)        AS flagged_smurfing,
    SUM(flag_cash_withdrawal) AS flagged_cash_withdrawal
FROM vw_fact_transactions;

-- Kontrola: 9 504 852 wierszy (bez zwielokrotnienia przez joiny),
-- flagi zgodne z tabelami reguł: 946 / 1 762 / 1 125.

SELECT amount_range, amount_range_order, COUNT(*)
FROM vw_fact_transactions
GROUP BY amount_range, amount_range_order
ORDER BY amount_range_order;
-- Kontrola: 7 przedziałów we właściwej kolejności, suma 9 504 852.

DROP VIEW IF EXISTS vw_sample_accounts;

CREATE VIEW vw_sample_accounts AS
WITH accounts (account_id, scheme, account_role) AS (
    -- konta wybrane w pliku 07
    VALUES
        ('7350260408_UK', 'Cash withdrawals',              'Laundering'),
        ('7961549830_UK', 'Cash withdrawals',              'Legitimate'),
        ('8156879059_UK', 'Structuring (label: Smurfing)', 'Laundering'),
        ('7133153926_UK', 'Structuring (label: Smurfing)', 'Legitimate'),
        ('434351836_UK',  'Smurfing (label: Structuring)', 'Laundering'),
        ('3442175873_UK', 'Smurfing (label: Structuring)', 'Legitimate')
),
account_tx AS (
    -- wszystkie transakcje kont (wysłane i odebrane)
    SELECT
        a.scheme,
        a.account_role,
        a.account_id,
        atc.transaction_id,
        CASE WHEN atc.sender_id = a.account_id THEN 'Outgoing' ELSE 'Incoming' END AS direction,
        CASE WHEN atc.sender_id = a.account_id THEN atc.receiver_id ELSE atc.sender_id END AS counterparty_id,
        atc.transaction_datetime,
        atc.transaction_datetime::date AS transaction_date,
        atc.amount,
        atc.payment_type,
        REPLACE(atc.laundering_type, '_', ' ') AS laundering_type,
        CASE WHEN atc.is_laundering = 1 THEN 'Laundering' ELSE 'Normal' END AS tx_class
    FROM accounts a
    JOIN aml_transactions_clean atc
      ON atc.sender_id = a.account_id
      OR atc.receiver_id = a.account_id
)
SELECT
    *,
    -- suma wpłat w parze konto-kontrahent z ostatnich 10 dni
    -- (jak w regule z pliku 04)
    SUM(amount) OVER (
        PARTITION BY account_id, counterparty_id, payment_type
        ORDER BY transaction_datetime
        RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW
    ) AS rolling_10d_sum
FROM account_tx;

SELECT scheme, account_role, tx_class, COUNT(*)
FROM vw_sample_accounts
GROUP BY scheme, account_role, tx_class
ORDER BY scheme, account_role, tx_class;
-- Kontrola: konta "Legitimate" mają wyłącznie transakcje Normal, konta "Laundering" zawierają transakcje prania.