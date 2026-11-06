# Banking Transaction Analysis (SQL project)

A SQL-first analysis of ~174k bank transactions across 250 customers / 311 accounts
(Nov 2025 – Oct 2026, amounts in INR). Built on SQLite; every analysis is plain SQL using
joins, CTEs and window functions (`LAG`, `FIRST_VALUE`, `ROW_NUMBER`, `NTILE`, moving averages).

## Project layout

| File | Purpose |
|---|---|
| `schema.sql` | Tables: `customers`, `accounts`, `transactions`, `fraud_labels` + indexes |
| `generate_data.py` | Builds `banking.db` with realistic synthetic data and injected fraud |
| `queries/01_fraud_detection.sql` | Rule-based fraud detection + evaluation |
| `queries/02_monthly_activity.sql` | Monthly account activity |
| `queries/03_spending_patterns.sql` | Customer spending patterns |
| `queries/04_balance_trends.sql` | Balance trends |
| `queries/05_high_value_transactions.sql` | High-value transactions |
| `run_queries.py` | Runs the query files, prints tables, saves CSVs to `results/` |
| `results/full_run.txt` | Sample output of a full run |

## Run it

```bash
python3 generate_data.py          # creates banking.db (~10 s)
python3 run_queries.py            # runs everything (~15 s)
python3 run_queries.py 01 03      # only selected files
sqlite3 banking.db                # or explore interactively
```

Requires Python 3 and SQLite 3.25+ (window functions). No other dependencies.

## Schema

```
customers (customer_id PK, full_name, home_city, segment, joined_on)
accounts  (account_id PK, customer_id FK, account_type, opened_on, opening_balance)
transactions (txn_id PK, account_id FK, txn_ts, txn_type, category, merchant,
              channel, city, amount, balance_after)
fraud_labels (txn_id PK FK, scenario)   -- ground truth, used only to score the rules
```

## What each file answers

**01 Fraud detection** – three rules, combined into the `flagged_txns` table:
1. *Card testing*: 5+ small (<500) online debits within 10 minutes, plus the large debit that follows.
2. *Amount anomaly*: debit ≥ 8× the account's average debit and ≥ 50,000, made at night (00–05h) or outside the customer's home city. Includes a naive-vs-refined comparison showing the amount-only version produced 240 false positives (11.8% precision) on legitimate big purchases, which the refined version removes.
3. *Geo-impossible*: card swipes in two different cities less than 60 minutes apart (uses `LAG`).
Then scores detection against ground truth and ranks accounts by risk.

**02 Monthly activity** – bank-wide credits/debits/net flow per month, MoM change, channel mix, a per-account statement with opening/closing balance, dormant-account check.

**03 Spending patterns** – spend by category, monthly spend by segment, weekday/weekend and time-of-day profile, top spenders with favourite category, savings rate by segment, spend concentration (`NTILE` quartiles), category trends.

**04 Balance trends** – month-end total and average balances (overall and by segment), steepest declines, growing vs shrinking accounts, low-balance risk, 30-day moving average.

**05 High-value transactions** – value bands, top debits, non-routine high-value categories, share of high-value debits that are flagged, most active high-value customers, unusual-hour large debits, a cash-structuring (just-under-threshold) check.

## Headline results (from the included synthetic run)

- Fraud rules catch all 154 injected fraud transactions with 1 false positive (99.4% precision overall).
- Spend is highly concentrated: the top quarter of customers account for ~57% of all debits.
- Savings rate: Business ≈ 62%, Premium ≈ 33%, Retail ≈ 18% (22 retail customers overspend).
- Rent/EMI is the largest debit category; shopping is the largest discretionary one.

## Caveats

The data is synthetic. Fraud was injected in the same three patterns the rules look for, so the
near-perfect recall/precision shows the SQL logic works, not how it would perform on real
data, where fraud is rarer, messier, and rules need tuning against labelled history. To use
real data, load it into the same four-table shape (`fraud_labels` is optional; only the scoring
queries need it).
