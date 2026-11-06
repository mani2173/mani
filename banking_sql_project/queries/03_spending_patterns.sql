-- ==========================================================================
-- 03  CUSTOMER SPENDING PATTERNS
-- ==========================================================================

-- Q: Spend by category (share of total debits, excluding rent/EMI & utilities = discretionary view)
SELECT category, COUNT(*) AS txns, ROUND(SUM(amount),0) AS total_spend,
       ROUND(AVG(amount),0) AS avg_ticket,
       ROUND(100.0*SUM(amount)/SUM(SUM(amount)) OVER (),1) AS pct_of_spend
FROM transactions WHERE txn_type='DEBIT'
GROUP BY category ORDER BY total_spend DESC;

-- Q: Average monthly spend by customer segment
WITH cust_month AS (
    SELECT c.customer_id, c.segment, strftime('%Y-%m', t.txn_ts) AS month, SUM(t.amount) AS spend
    FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
    WHERE t.txn_type='DEBIT' GROUP BY c.customer_id, month
)
SELECT segment, COUNT(DISTINCT customer_id) AS customers,
       ROUND(AVG(spend),0) AS avg_monthly_spend,
       ROUND(MAX(spend),0) AS peak_monthly_spend
FROM cust_month GROUP BY segment ORDER BY avg_monthly_spend DESC;

-- Q: Weekday vs weekend, and time-of-day spending profile
SELECT CASE WHEN strftime('%w', txn_ts) IN ('0','6') THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       CASE WHEN CAST(strftime('%H', txn_ts) AS INT) < 6  THEN '1 Night (0-6)'
            WHEN CAST(strftime('%H', txn_ts) AS INT) < 12 THEN '2 Morning (6-12)'
            WHEN CAST(strftime('%H', txn_ts) AS INT) < 18 THEN '3 Afternoon (12-18)'
            ELSE '4 Evening (18-24)' END AS time_band,
       COUNT(*) AS txns, ROUND(AVG(amount),0) AS avg_ticket, ROUND(SUM(amount),0) AS total_spend
FROM transactions WHERE txn_type='DEBIT'
GROUP BY day_type, time_band ORDER BY day_type, time_band;

-- Q: Top 10 spenders and their favourite category
WITH spend AS (
    SELECT c.customer_id, c.full_name, c.segment, t.category, SUM(t.amount) AS cat_spend
    FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
    WHERE t.txn_type='DEBIT' AND t.category NOT IN ('Rent/EMI','Utilities')
    GROUP BY c.customer_id, t.category
),
ranked AS (
    SELECT *, SUM(cat_spend) OVER (PARTITION BY customer_id) AS total_spend,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY cat_spend DESC) AS rk
    FROM spend
)
SELECT customer_id, full_name, segment, ROUND(total_spend,0) AS total_spend,
       category AS top_category, ROUND(100.0*cat_spend/total_spend,1) AS top_cat_pct
FROM ranked WHERE rk=1 ORDER BY total_spend DESC LIMIT 10;

-- Q: Savings rate by segment (1 - debits/credits)
WITH cust AS (
    SELECT c.customer_id, c.segment,
           SUM(CASE WHEN t.txn_type='CREDIT' THEN t.amount END) AS cr,
           SUM(CASE WHEN t.txn_type='DEBIT'  THEN t.amount END) AS dr
    FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
    GROUP BY c.customer_id
)
SELECT segment, COUNT(*) AS customers,
       ROUND(100.0*(1 - SUM(dr)/SUM(cr)),1) AS savings_rate_pct,
       SUM(dr > cr) AS customers_overspending
FROM cust GROUP BY segment;

-- Q: Customer spend quartiles (NTILE) - how concentrated is spending?
WITH cust AS (
    SELECT c.customer_id, SUM(t.amount) AS spend
    FROM transactions t JOIN accounts a USING (account_id) JOIN customers c USING (customer_id)
    WHERE t.txn_type='DEBIT' GROUP BY c.customer_id
),
q AS (SELECT *, NTILE(4) OVER (ORDER BY spend DESC) AS quartile FROM cust)
SELECT quartile, COUNT(*) AS customers, ROUND(SUM(spend),0) AS spend,
       ROUND(100.0*SUM(spend)/SUM(SUM(spend)) OVER (),1) AS pct_of_total
FROM q GROUP BY quartile ORDER BY quartile;

-- Q: Month-by-month category trend for the top 3 categories
SELECT strftime('%Y-%m', txn_ts) AS month,
       ROUND(SUM(CASE WHEN category='Groceries' THEN amount END),0) AS groceries,
       ROUND(SUM(CASE WHEN category='Dining'    THEN amount END),0) AS dining,
       ROUND(SUM(CASE WHEN category='Shopping'  THEN amount END),0) AS shopping
FROM transactions WHERE txn_type='DEBIT' GROUP BY month ORDER BY month;
