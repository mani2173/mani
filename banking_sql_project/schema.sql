-- Banking Transaction Analysis: schema (SQLite)
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS fraud_labels;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id  INTEGER PRIMARY KEY,
    full_name    TEXT NOT NULL,
    home_city    TEXT NOT NULL,
    segment      TEXT NOT NULL CHECK (segment IN ('Retail','Premium','Business')),
    joined_on    DATE NOT NULL
);

CREATE TABLE accounts (
    account_id       INTEGER PRIMARY KEY,
    customer_id      INTEGER NOT NULL REFERENCES customers(customer_id),
    account_type     TEXT NOT NULL CHECK (account_type IN ('Savings','Current')),
    opened_on        DATE NOT NULL,
    opening_balance  REAL NOT NULL
);

CREATE TABLE transactions (
    txn_id         INTEGER PRIMARY KEY,
    account_id     INTEGER NOT NULL REFERENCES accounts(account_id),
    txn_ts         TEXT NOT NULL,              -- 'YYYY-MM-DD HH:MM:SS'
    txn_type       TEXT NOT NULL CHECK (txn_type IN ('CREDIT','DEBIT')),
    category       TEXT NOT NULL,
    merchant       TEXT,
    channel        TEXT NOT NULL,              -- CARD, UPI, ONLINE, ATM, NETBANKING
    city           TEXT NOT NULL,              -- 'Online' for card-not-present
    amount         REAL NOT NULL CHECK (amount > 0),
    balance_after  REAL NOT NULL
);

-- Ground truth used ONLY to evaluate the fraud rules (not by the detection logic)
CREATE TABLE fraud_labels (
    txn_id    INTEGER PRIMARY KEY REFERENCES transactions(txn_id),
    scenario  TEXT NOT NULL
);

CREATE INDEX idx_txn_account_ts ON transactions(account_id, txn_ts);
CREATE INDEX idx_txn_ts         ON transactions(txn_ts);
CREATE INDEX idx_txn_category   ON transactions(category);
CREATE INDEX idx_acct_customer  ON accounts(customer_id);
