-- ==========================================================================
-- 01  FRAUD DETECTION  (SQLite; uses window functions)
-- Three rule-based detectors, combined into one scored list, then evaluated
-- against the ground-truth fraud_labels table.
-- ==========================================================================

-- Q: Rule 1 - Card testing: >=5 small online debits (<500) within 10 min, per account
WITH small AS (
    SELECT txn_id, account_id, txn_ts, amount, CAST(strftime('%s', txn_ts) AS INTEGER) AS ts
    FROM transactions
    WHERE txn_type = 'DEBIT' AND channel = 'ONLINE' AND amount < 500
),
bursts AS (
    SELECT a.account_id, a.txn_id AS start_txn, a.txn_ts AS burst_start, COUNT(*) AS txns_in_10min
    FROM small a
    JOIN small b
      ON b.account_id = a.account_id
     AND b.ts BETWEEN a.ts AND a.ts + 600
    GROUP BY a.account_id, a.txn_id
    HAVING COUNT(*) >= 5
)
SELECT account_id, MIN(burst_start) AS first_burst, MAX(txns_in_10min) AS max_burst_size,
       COUNT(DISTINCT date(burst_start)) AS days_with_bursts
FROM bursts
GROUP BY account_id
ORDER BY max_burst_size DESC, account_id
LIMIT 15;

-- Q: Rule 2 - Amount anomaly: debit >= 8x account's typical debit, >= 50,000, AND (00-05h OR outside home city)
WITH acct_stats AS (
    SELECT account_id, AVG(amount) AS avg_debit
    FROM transactions
    WHERE txn_type = 'DEBIT' AND category NOT IN ('Rent/EMI')
    GROUP BY account_id
)
SELECT t.txn_id, t.account_id, t.txn_ts, t.merchant, t.channel, t.city, c.home_city,
       ROUND(t.amount, 0) AS amount, ROUND(t.amount / s.avg_debit, 1) AS times_avg,
       CASE WHEN CAST(strftime('%H', t.txn_ts) AS INT) < 5 THEN 'night' ELSE 'day' END AS tod
FROM transactions t
JOIN acct_stats s USING (account_id)
JOIN accounts a ON a.account_id = t.account_id
JOIN customers c ON c.customer_id = a.customer_id
WHERE t.txn_type = 'DEBIT' AND t.category NOT IN ('Rent/EMI')
  AND t.amount >= 50000 AND t.amount >= 8 * s.avg_debit
  AND (CAST(strftime('%H', t.txn_ts) AS INT) < 5 OR (t.city <> 'Online' AND t.city <> c.home_city))
ORDER BY times_avg DESC
LIMIT 15;

-- Q: Rule 2 tuning - naive amount-only rule vs refined rule (false positives on legit big purchases)
WITH acct_stats AS (
    SELECT account_id, AVG(amount) AS avg_debit FROM transactions
    WHERE txn_type='DEBIT' AND category<>'Rent/EMI' GROUP BY account_id
),
cand AS (
    SELECT t.txn_id,
           (CAST(strftime('%H', t.txn_ts) AS INT) < 5 OR (t.city<>'Online' AND t.city<>c.home_city)) AS refined
    FROM transactions t JOIN acct_stats s USING (account_id)
    JOIN accounts a ON a.account_id=t.account_id JOIN customers c ON c.customer_id=a.customer_id
    WHERE t.txn_type='DEBIT' AND t.category<>'Rent/EMI' AND t.amount>=50000 AND t.amount>=8*s.avg_debit
)
SELECT 'naive (amount only)' AS version, COUNT(*) AS flagged,
       SUM(txn_id IN (SELECT txn_id FROM fraud_labels)) AS true_fraud,
       COUNT(*) - SUM(txn_id IN (SELECT txn_id FROM fraud_labels)) AS false_positives,
       ROUND(100.0*SUM(txn_id IN (SELECT txn_id FROM fraud_labels))/COUNT(*),1) AS precision_pct
FROM cand
UNION ALL
SELECT 'refined (+ night/away)', COUNT(*), SUM(txn_id IN (SELECT txn_id FROM fraud_labels)),
       COUNT(*) - SUM(txn_id IN (SELECT txn_id FROM fraud_labels)),
       ROUND(100.0*SUM(txn_id IN (SELECT txn_id FROM fraud_labels))/COUNT(*),1)
FROM cand WHERE refined;

-- Q: Rule 3 - Geo-impossible: card txns in two different physical cities < 60 min apart
WITH card AS (
    SELECT txn_id, account_id, txn_ts, city, amount,
           LAG(txn_id) OVER w AS prev_txn,
           LAG(txn_ts) OVER w AS prev_ts,
           LAG(city)   OVER w AS prev_city
    FROM transactions
    WHERE channel IN ('CARD','ATM') AND city <> 'Online'
    WINDOW w AS (PARTITION BY account_id ORDER BY txn_ts)
)
SELECT account_id, prev_city, city AS this_city, prev_ts, txn_ts,
       ROUND((julianday(txn_ts) - julianday(prev_ts)) * 1440, 1) AS minutes_apart,
       ROUND(amount, 2) AS amount
FROM card
WHERE prev_city IS NOT NULL AND prev_city <> city
  AND (julianday(txn_ts) - julianday(prev_ts)) * 1440 < 60
ORDER BY txn_ts
LIMIT 15;

-- Q: Combined flagged transactions (txn-level) with rule that fired
DROP TABLE IF EXISTS flagged_txns;
CREATE TABLE flagged_txns AS
WITH small AS (
    SELECT txn_id, account_id, CAST(strftime('%s', txn_ts) AS INTEGER) AS ts
    FROM transactions
    WHERE txn_type='DEBIT' AND channel='ONLINE' AND amount < 500
),
burst_starts AS (   -- small txns that begin a window holding >= 5 small txns within 10 min
    SELECT a.txn_id, a.account_id, a.ts
    FROM small a JOIN small b
      ON b.account_id=a.account_id AND b.ts BETWEEN a.ts AND a.ts+600
    GROUP BY a.txn_id HAVING COUNT(*) >= 5
),
burst_ids AS (      -- every small txn sitting inside such a window
    SELECT DISTINCT b.txn_id
    FROM burst_starts a JOIN small b
      ON b.account_id=a.account_id AND b.ts BETWEEN a.ts AND a.ts+600
),
burst_followup AS (  -- big online debit within 15 min after a burst starts
    SELECT DISTINCT t.txn_id
    FROM burst_starts s
    JOIN transactions t ON t.account_id=s.account_id
    WHERE t.txn_type='DEBIT' AND t.channel='ONLINE' AND t.amount >= 20000
      AND CAST(strftime('%s', t.txn_ts) AS INTEGER) BETWEEN s.ts AND s.ts + 900
),
acct_stats AS (
    SELECT account_id, AVG(amount) AS avg_debit
    FROM transactions WHERE txn_type='DEBIT' AND category<>'Rent/EMI' GROUP BY account_id
),
big AS (
    SELECT t.txn_id
    FROM transactions t JOIN acct_stats s USING(account_id)
    JOIN accounts a ON a.account_id=t.account_id JOIN customers c ON c.customer_id=a.customer_id
    WHERE t.txn_type='DEBIT' AND t.category<>'Rent/EMI'
      AND t.amount >= 50000 AND t.amount >= 8*s.avg_debit
      AND (CAST(strftime('%H', t.txn_ts) AS INT) < 5 OR (t.city<>'Online' AND t.city<>c.home_city))
),
geo AS (
    SELECT txn_id FROM (
        SELECT txn_id, city,
               LAG(city) OVER w AS prev_city, LAG(txn_ts) OVER w AS prev_ts, txn_ts
        FROM transactions WHERE channel IN ('CARD','ATM') AND city<>'Online'
        WINDOW w AS (PARTITION BY account_id ORDER BY txn_ts))
    WHERE prev_city IS NOT NULL AND prev_city<>city
      AND (julianday(txn_ts)-julianday(prev_ts))*1440 < 60
)
SELECT txn_id, 'CARD_TESTING' AS rule FROM burst_ids
UNION ALL SELECT txn_id, 'CARD_TESTING' FROM burst_followup
UNION ALL SELECT txn_id, 'LARGE_ANOMALY' FROM big
UNION ALL SELECT txn_id, 'GEO_IMPOSSIBLE' FROM geo;

SELECT rule, COUNT(*) AS flagged_txns, COUNT(DISTINCT t.account_id) AS accounts
FROM flagged_txns f JOIN transactions t USING (txn_id)
GROUP BY rule ORDER BY flagged_txns DESC;

-- Q: Overall detection vs ground truth, by true fraud scenario (was the txn caught by ANY rule?)
SELECT l.scenario, COUNT(*) AS fraud_txns,
       SUM(l.txn_id IN (SELECT txn_id FROM flagged_txns)) AS caught,
       ROUND(100.0*SUM(l.txn_id IN (SELECT txn_id FROM flagged_txns))/COUNT(*),1) AS recall_pct
FROM fraud_labels l GROUP BY l.scenario
UNION ALL
SELECT 'ALL', COUNT(*), SUM(txn_id IN (SELECT txn_id FROM flagged_txns)),
       ROUND(100.0*SUM(txn_id IN (SELECT txn_id FROM flagged_txns))/COUNT(*),1)
FROM fraud_labels;

-- Q: Overall precision - of all distinct flagged transactions, how many are truly fraud?
WITH f AS (SELECT DISTINCT txn_id FROM flagged_txns)
SELECT COUNT(*) AS flagged_txns,
       SUM(txn_id IN (SELECT txn_id FROM fraud_labels)) AS true_fraud,
       COUNT(*) - SUM(txn_id IN (SELECT txn_id FROM fraud_labels)) AS false_positives,
       ROUND(100.0*SUM(txn_id IN (SELECT txn_id FROM fraud_labels))/COUNT(*),1) AS precision_pct
FROM f;

-- Q: Accounts ranked by fraud-risk score (distinct rules fired, flagged value)
SELECT t.account_id, c.full_name, c.segment,
       COUNT(DISTINCT f.rule) AS rules_fired,
       COUNT(DISTINCT f.txn_id) AS flagged_txns,
       ROUND(SUM(t.amount),2) AS flagged_amount
FROM flagged_txns f
JOIN transactions t USING (txn_id)
JOIN accounts a ON a.account_id = t.account_id
JOIN customers c ON c.customer_id = a.customer_id
GROUP BY t.account_id
ORDER BY rules_fired DESC, flagged_amount DESC
LIMIT 15;
