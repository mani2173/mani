"""Run every query file in queries/ against banking.db and print results as tables.

Usage:  python run_queries.py            # all files
        python run_queries.py 01 03      # only files starting with these prefixes
Also writes each result to results/<file>__<n>.csv
"""
import csv
import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).parent
DB = ROOT / "banking.db"
OUT = ROOT / "results"
OUT.mkdir(exist_ok=True)


def split_queries(text):
    """Split a .sql file into (title, sql) blocks using '-- Q: title' markers."""
    parts = re.split(r"^-- Q: (.*)$", text, flags=re.M)
    return [(parts[i].strip(), parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def render(cols, rows, limit=20):
    if not rows:
        return "  (no rows)"
    data = [[("" if v is None else str(v)) for v in r] for r in rows[:limit]]
    w = [max(len(c), *(len(r[i]) for r in data)) for i, c in enumerate(cols)]
    line = "  " + " | ".join(c.ljust(w[i]) for i, c in enumerate(cols))
    sep = "  " + "-+-".join("-" * x for x in w)
    body = ["  " + " | ".join(r[i].ljust(w[i]) for i in range(len(cols))) for r in data]
    more = f"\n  ... {len(rows) - limit} more rows" if len(rows) > limit else ""
    return "\n".join([line, sep, *body]) + more


def main():
    prefixes = sys.argv[1:]
    con = sqlite3.connect(DB)
    # indexes are not stored in the shipped database (keeps it small); build them on first run
    for stmt in (
        "CREATE INDEX IF NOT EXISTS idx_txn_account_ts ON transactions(account_id, txn_ts)",
        "CREATE INDEX IF NOT EXISTS idx_txn_ts ON transactions(txn_ts)",
        "CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(category)",
        "CREATE INDEX IF NOT EXISTS idx_acct_customer ON accounts(customer_id)",
    ):
        con.execute(stmt)
    for f in sorted((ROOT / "queries").glob("*.sql")):
        if prefixes and not any(f.name.startswith(p) for p in prefixes):
            continue
        print("\n" + "=" * 78 + f"\n{f.name}\n" + "=" * 78)
        for n, (title, sql) in enumerate(split_queries(f.read_text()), 1):
            print(f"\n[{n}] {title}")
            cur = None
            # a block may contain setup statements (DROP/CREATE VIEW) followed by a SELECT
            stmts = [s.strip() for s in re.split(r";\s*(?:\n|$)", sql) if s.strip()]
            for s in stmts:
                s = re.sub(r"^\s*--.*$", "", s, flags=re.M).strip()
                if not s:
                    continue
                cur = con.execute(s)
            if cur is not None and cur.description:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchall()
                print(render(cols, rows))
                with open(OUT / f"{f.stem}__{n}.csv", "w", newline="") as fh:
                    w = csv.writer(fh)
                    w.writerow(cols)
                    w.writerows(rows)
    con.close()


if __name__ == "__main__":
    main()
