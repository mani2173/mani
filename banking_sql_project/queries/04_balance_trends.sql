-- ==========================================================================
-- 04  BALANCE TRENDS
-- ==========================================================================

-- Q: Total bank balance at each month-end (sum of each account's last balance in month)
WITH last_bal AS (
    SELECT account_id, strftime('%Y-%m', txn_ts) AS month, balance_after,
           ROW_NUMBER() OVER (PARTITION BY account_id, strftime('%Y-%m', txn_ts)
                              ORDER BY txn_ts DESC, txn_id DESC) AS rn
    FROM transactions
)
SELECT month, COUNT(*) AS accounts, ROUND(SUM(balance_after),0) AS total_balance,
       ROUND(AVG(balance_after),0) AS avg_balance
FROM last_bal WHERE rn=1 GROUP BY month ORDER BY month;

-- Q: Average month-end balance by segment
WITH last_bal AS (
    SELECT t.account_id, strftime('%Y-%m', t.txn_ts) AS month, t.balance_after,
           ROW_NUMBER() OVER (PARTITION BY t.account_id, strftime('%Y-%m', t.txn_ts)
                              ORDER BY t.txn_ts DESC, t.txn_id DESC) AS rn
    FROM transactions t
)
SELECT l.month,
       ROUND(AVG(CASE WHEN c.segment='Retail'   THEN l.balance_after END),0) AS retail,
       ROUND(AVG(CASE WHEN c.segment='Premium'  THEN l.balance_after END),0) AS premium,
       ROUND(AVG(CASE WHEN c.segment='Business' THEN l.balance_after END),0) AS business
FROM last_bal l JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
WHERE l.rn=1 GROUP BY l.month ORDER BY l.month;

-- Q: Accounts with the steepest balance decline (first vs last balance)
WITH ends AS (
    SELECT account_id,
           FIRST_VALUE(balance_after) OVER (PARTITION BY account_id ORDER BY txn_ts, txn_id) AS first_bal,
           FIRST_VALUE(balance_after) OVER (PARTITION BY account_id ORDER BY txn_ts DESC, txn_id DESC) AS last_bal
    FROM transactions
)
SELECT account_id, ROUND(first_bal,0) AS first_bal, ROUND(last_bal,0) AS last_bal,
       ROUND(last_bal-first_bal,0) AS change,
       ROUND(100.0*(last_bal-first_bal)/first_bal,1) AS change_pct
FROM ends GROUP BY account_id ORDER BY change ASC LIMIT 10;

-- Q: Growing vs shrinking accounts
WITH ends AS (
    SELECT account_id,
           FIRST_VALUE(balance_after) OVER (PARTITION BY account_id ORDER BY txn_ts, txn_id) AS f,
           FIRST_VALUE(balance_after) OVER (PARTITION BY account_id ORDER BY txn_ts DESC, txn_id DESC) AS l
    FROM transactions
),
per AS (SELECT account_id, MAX(l)-MAX(f) AS delta FROM ends GROUP BY account_id)
SELECT CASE WHEN delta > 0 THEN 'Growing' ELSE 'Shrinking/flat' END AS trend,
       COUNT(*) AS accounts, ROUND(AVG(delta),0) AS avg_change
FROM per GROUP BY trend;

-- Q: Low-balance risk - accounts whose balance fell below 5,000 and how often
SELECT t.account_id, c.segment, COUNT(*) AS low_balance_txns,
       ROUND(MIN(t.balance_after),0) AS lowest_balance, MIN(t.txn_ts) AS first_seen
FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
WHERE t.balance_after < 5000
GROUP BY t.account_id ORDER BY low_balance_txns DESC LIMIT 10;

-- Q: 30-day moving average balance for the busiest account
WITH acct AS (SELECT account_id FROM transactions GROUP BY account_id ORDER BY COUNT(*) DESC LIMIT 1),
daily AS (
    SELECT date(txn_ts) AS d, balance_after,
           ROW_NUMBER() OVER (PARTITION BY date(txn_ts) ORDER BY txn_ts DESC, txn_id DESC) AS rn
    FROM transactions WHERE account_id=(SELECT account_id FROM acct)
),
eod AS (SELECT d, balance_after FROM daily WHERE rn=1)
SELECT d AS day, ROUND(balance_after,0) AS end_of_day_balance,
       ROUND(AVG(balance_after) OVER (ORDER BY d ROWS BETWEEN 29 PRECEDING AND CURRENT ROW),0) AS moving_avg_30d
FROM eod ORDER BY d DESC LIMIT 10;
