-- ==========================================================================
-- 05  HIGH-VALUE TRANSACTIONS
-- ==========================================================================

-- Q: Threshold buckets - how many transactions fall in each value band
SELECT CASE WHEN amount >= 200000 THEN '4 >= 2,00,000'
            WHEN amount >= 100000 THEN '3 1,00,000 - 2,00,000'
            WHEN amount >=  50000 THEN '2 50,000 - 1,00,000'
            WHEN amount >=  10000 THEN '1 10,000 - 50,000'
            ELSE '0 < 10,000' END AS band,
       COUNT(*) AS txns, ROUND(SUM(amount),0) AS total_value
FROM transactions GROUP BY band ORDER BY band DESC;

-- Q: Top 15 largest debits (with customer context)
SELECT t.txn_id, t.txn_ts, c.full_name, c.segment, t.category, t.merchant, t.channel, t.city,
       ROUND(t.amount,0) AS amount
FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
WHERE t.txn_type='DEBIT'
ORDER BY t.amount DESC LIMIT 15;

-- Q: High-value (>= 50,000) transactions that are NOT regular salary/rent/business flows, by category
SELECT category, COUNT(*) AS txns, ROUND(SUM(amount),0) AS total_value, ROUND(AVG(amount),0) AS avg_value
FROM transactions
WHERE amount >= 50000 AND category NOT IN ('Salary','Business Receipts','Rent/EMI')
GROUP BY category ORDER BY total_value DESC;

-- Q: Share of high-value (>= 50,000) debits that are on the fraud-flag list
SELECT COUNT(*) AS high_value_debits,
       SUM(txn_id IN (SELECT txn_id FROM flagged_txns)) AS flagged,
       ROUND(100.0*SUM(txn_id IN (SELECT txn_id FROM flagged_txns))/COUNT(*),1) AS pct_flagged
FROM transactions
WHERE txn_type='DEBIT' AND amount >= 50000 AND category NOT IN ('Rent/EMI');

-- Q: Customers with the most high-value activity (>= 50,000, any direction)
SELECT c.customer_id, c.full_name, c.segment,
       COUNT(*) AS hv_txns, ROUND(SUM(t.amount),0) AS hv_total,
       SUM(t.txn_type='DEBIT') AS hv_debits, SUM(t.txn_type='CREDIT') AS hv_credits
FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
WHERE t.amount >= 50000
GROUP BY c.customer_id ORDER BY hv_total DESC LIMIT 10;

-- Q: Unusual hour - high-value (>= 25,000) debits made between 00:00 and 05:00
SELECT t.txn_id, t.txn_ts, t.account_id, t.channel, t.merchant, ROUND(t.amount,0) AS amount
FROM transactions t
WHERE t.txn_type='DEBIT' AND t.amount >= 25000
  AND CAST(strftime('%H', t.txn_ts) AS INT) < 5
ORDER BY t.amount DESC LIMIT 15;

-- Q: AML-style structuring check - accounts with 3+ cash/ATM debits of 9,000-9,999 in a month
SELECT account_id, strftime('%Y-%m', txn_ts) AS month, COUNT(*) AS near_threshold_txns, ROUND(SUM(amount),0) AS total
FROM transactions
WHERE txn_type='DEBIT' AND category='Cash Withdrawal' AND amount BETWEEN 9000 AND 9999
GROUP BY account_id, month HAVING COUNT(*) >= 3;
