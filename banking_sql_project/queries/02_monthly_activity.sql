-- ==========================================================================
-- 02  MONTHLY ACCOUNT ACTIVITY
-- ==========================================================================

-- Q: Bank-wide monthly activity
SELECT strftime('%Y-%m', txn_ts) AS month,
       COUNT(*) AS txns,
       SUM(txn_type='CREDIT') AS credit_txns,
       SUM(txn_type='DEBIT')  AS debit_txns,
       ROUND(SUM(CASE WHEN txn_type='CREDIT' THEN amount END),0) AS total_credits,
       ROUND(SUM(CASE WHEN txn_type='DEBIT'  THEN amount END),0) AS total_debits,
       ROUND(SUM(CASE WHEN txn_type='CREDIT' THEN amount ELSE -amount END),0) AS net_flow,
       COUNT(DISTINCT account_id) AS active_accounts
FROM transactions
GROUP BY month
ORDER BY month;

-- Q: Month-over-month change in debit volume (LAG)
WITH m AS (
    SELECT strftime('%Y-%m', txn_ts) AS month, SUM(amount) AS debits
    FROM transactions WHERE txn_type='DEBIT' GROUP BY month
)
SELECT month, ROUND(debits,0) AS debits,
       ROUND(LAG(debits) OVER (ORDER BY month),0) AS prev_month,
       ROUND(100.0*(debits - LAG(debits) OVER (ORDER BY month)) / LAG(debits) OVER (ORDER BY month),1) AS mom_pct
FROM m ORDER BY month;

-- Q: Monthly activity by channel (txn counts)
SELECT strftime('%Y-%m', txn_ts) AS month,
       SUM(channel='UPI') AS upi, SUM(channel='CARD') AS card, SUM(channel='ONLINE') AS online,
       SUM(channel='NETBANKING') AS netbanking, SUM(channel='ATM') AS atm
FROM transactions GROUP BY month ORDER BY month;

-- Q: Account statement - monthly summary for one account (opening/closing balance)
WITH acct AS (SELECT account_id FROM transactions GROUP BY account_id ORDER BY COUNT(*) DESC LIMIT 1),
ranked AS (
    SELECT t.*, strftime('%Y-%m', txn_ts) AS month,
           ROW_NUMBER() OVER (PARTITION BY account_id, strftime('%Y-%m', txn_ts) ORDER BY txn_ts, txn_id)      AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY account_id, strftime('%Y-%m', txn_ts) ORDER BY txn_ts DESC, txn_id DESC) AS rn_last
    FROM transactions t WHERE account_id = (SELECT account_id FROM acct)
)
SELECT account_id, month,
       ROUND(MAX(CASE WHEN rn_first=1 THEN balance_after - CASE txn_type WHEN 'CREDIT' THEN amount ELSE -amount END END),2) AS opening_balance,
       ROUND(SUM(CASE WHEN txn_type='CREDIT' THEN amount ELSE 0 END),2) AS credits,
       ROUND(SUM(CASE WHEN txn_type='DEBIT'  THEN amount ELSE 0 END),2) AS debits,
       ROUND(MAX(CASE WHEN rn_last=1 THEN balance_after END),2) AS closing_balance,
       COUNT(*) AS txns
FROM ranked GROUP BY account_id, month ORDER BY month;

-- Q: Dormant accounts - no activity in the last 60 days of the data
SELECT a.account_id, c.full_name, c.segment, MAX(t.txn_ts) AS last_txn,
       CAST(julianday('2026-10-31') - julianday(MAX(t.txn_ts)) AS INTEGER) AS days_inactive
FROM accounts a JOIN customers c USING (customer_id)
LEFT JOIN transactions t ON t.account_id = a.account_id
GROUP BY a.account_id
HAVING last_txn IS NULL OR days_inactive > 60
ORDER BY days_inactive DESC
LIMIT 15;
