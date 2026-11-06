"""Generate a realistic synthetic banking dataset into banking.db (SQLite).

Period: 2025-11-01 .. 2026-10-31 (12 months). Amounts in INR.
Fraud is injected in three scenarios so the SQL detection rules can be evaluated:
  CARD_TESTING, LARGE_ANOMALY, GEO_IMPOSSIBLE
"""
import datetime as dt
import math
import pathlib
import random
import sqlite3

random.seed(42)
ROOT = pathlib.Path(__file__).parent
DB = ROOT / "banking.db"

START = dt.date(2025, 11, 1)
END = dt.date(2026, 10, 31)
N_CUSTOMERS = 250

CITIES = ["Hyderabad", "Mumbai", "Delhi", "Bengaluru", "Chennai", "Pune", "Kolkata", "Ahmedabad"]
FIRST = ["Aarav", "Vivaan", "Aditya", "Sai", "Arjun", "Rohan", "Karthik", "Rahul", "Ananya", "Diya",
         "Priya", "Sneha", "Kavya", "Meera", "Ishita", "Neha", "Pooja", "Divya", "Ravi", "Suresh",
         "Lakshmi", "Anil", "Sunita", "Vikram", "Deepa"]
LAST = ["Sharma", "Reddy", "Patel", "Iyer", "Nair", "Gupta", "Singh", "Rao", "Das", "Mehta",
        "Kumar", "Joshi", "Verma", "Naidu", "Chopra"]

# category -> (merchants, median amount, channel weights, daily-pick weight)
CATS = {
    "Groceries":     (["BigBasket", "DMart", "Reliance Fresh", "More Supermarket"], 900,
                      {"UPI": 5, "CARD": 3, "ONLINE": 2}, 22),
    "Dining":        (["Swiggy", "Zomato", "Paradise Biryani", "Cafe Coffee Day"], 550,
                      {"UPI": 5, "CARD": 3, "ONLINE": 3}, 18),
    "Shopping":      (["Amazon", "Flipkart", "Myntra", "Lifestyle"], 1800,
                      {"ONLINE": 6, "CARD": 4, "UPI": 1}, 14),
    "Fuel":          (["HP Petrol Pump", "Indian Oil", "Shell"], 1500,
                      {"CARD": 5, "UPI": 4}, 8),
    "Travel":        (["Uber", "Ola", "IRCTC", "MakeMyTrip", "IndiGo"], 700,
                      {"ONLINE": 5, "UPI": 4, "CARD": 2}, 10),
    "Entertainment": (["Netflix", "BookMyShow", "Spotify", "PVR Cinemas"], 450,
                      {"ONLINE": 5, "CARD": 3, "UPI": 2}, 6),
    "Healthcare":    (["Apollo Pharmacy", "MedPlus", "Practo"], 800,
                      {"UPI": 4, "CARD": 3}, 5),
    "Cash Withdrawal": (["ATM"], 5000, {"ATM": 1}, 3),
}
SEG_MULT = {"Retail": 1.0, "Premium": 2.2, "Business": 3.0}
# scales discretionary spend so each segment lands at a plausible savings rate
SPEND_SCALE = {"Retail": 0.5, "Premium": 0.55, "Business": 0.8}
BIG_TICKET = ["Tanishq Jewellers", "Croma Electronics", "MakeMyTrip Holidays", "Reliance Digital", "Urban Ladder"]
SALARY_RANGE = {"Retail": (35_000, 80_000), "Premium": (120_000, 300_000), "Business": (250_000, 700_000)}
OPEN_BAL = {"Retail": (10_000, 80_000), "Premium": (80_000, 400_000), "Business": (150_000, 800_000)}


def rand_ts(day: dt.date, h0=8, h1=22) -> dt.datetime:
    secs = random.randint(h0 * 3600, h1 * 3600 - 1)
    return dt.datetime.combine(day, dt.time()) + dt.timedelta(seconds=secs)


def months():
    d = dt.date(START.year, START.month, 1)
    while d <= END:
        yield d
        d = dt.date(d.year + (d.month // 12), d.month % 12 + 1, 1)


def main():
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    con.executescript((ROOT / "schema.sql").read_text())

    customers, accounts = [], []
    acct_id = 1
    for cid in range(1, N_CUSTOMERS + 1):
        seg = random.choices(["Retail", "Premium", "Business"], [70, 20, 10])[0]
        city = random.choice(CITIES)
        name = f"{random.choice(FIRST)} {random.choice(LAST)}"
        joined = START - dt.timedelta(days=random.randint(90, 2500))
        customers.append((cid, name, city, seg, joined.isoformat()))
        for k in range(random.choices([1, 2], [75, 25])[0]):
            atype = "Current" if seg == "Business" and k == 0 else "Savings"
            ob = round(random.uniform(*OPEN_BAL[seg]), 2)
            accounts.append((acct_id, cid, atype, joined.isoformat(), ob, city, seg))
            acct_id += 1

    # txns[account_id] = list of dicts
    txns = {a[0]: [] for a in accounts}
    all_days = [START + dt.timedelta(days=i) for i in range((END - START).days + 1)]

    def add(acct, ts, ttype, cat, merchant, channel, city, amount, fraud=None):
        txns[acct].append(dict(ts=ts, type=ttype, cat=cat, merchant=merchant, channel=channel,
                               city=city, amount=round(amount, 2), fraud=fraud))

    for (aid, cid, atype, opened, ob, home, seg) in accounts:
        mult = SEG_MULT[seg]
        lo, hi = SALARY_RANGE[seg]
        salary = random.uniform(lo, hi)

        # trips: whole days spent in another city
        trip_days = {}
        for _ in range(random.choice([0, 1, 1, 2])):
            tcity = random.choice([c for c in CITIES if c != home])
            s = random.choice(all_days[:-5])
            for j in range(random.randint(2, 4)):
                trip_days[s + dt.timedelta(days=j)] = tcity

        for m in months():
            # income
            if seg == "Business":
                for _ in range(random.randint(3, 5)):
                    d = m + dt.timedelta(days=random.randint(0, 27))
                    add(aid, rand_ts(d, 10, 17), "CREDIT", "Business Receipts", "Client Payment",
                        "NETBANKING", "Online", salary * random.uniform(0.2, 0.5))
            else:
                d = m + dt.timedelta(days=random.randint(0, 4))
                add(aid, rand_ts(d, 9, 11), "CREDIT", "Salary", "Employer Payroll", "NETBANKING",
                    "Online", salary * random.uniform(0.97, 1.03))
            # occasional legitimate big-ticket purchase (daytime, in-person card, home city)
            if seg != "Retail" and random.random() < 0.25:
                d = m + dt.timedelta(days=random.randint(0, 27))
                add(aid, rand_ts(d, 11, 19), "DEBIT", "Shopping", random.choice(BIG_TICKET), "CARD",
                    home, random.uniform(40_000, 140_000))
            # fixed obligations
            d = m + dt.timedelta(days=random.randint(5, 9))
            add(aid, rand_ts(d, 9, 12), "DEBIT", "Rent/EMI", "Landlord/Loan EMI", "NETBANKING",
                "Online", salary * random.uniform(0.22, 0.32))
            d = m + dt.timedelta(days=random.randint(10, 15))
            add(aid, rand_ts(d, 9, 20), "DEBIT", "Utilities", random.choice(["TSSPDCL", "ACT Fibernet", "Airtel", "Jio"]),
                "NETBANKING", "Online", random.uniform(600, 3500) * mult ** 0.5)

        # everyday spending
        for day in all_days:
            if day < dt.date.fromisoformat(opened):
                continue
            n = random.choices([0, 1, 2, 3, 4], [30, 32, 22, 11, 5])[0]
            if day.weekday() >= 5:
                n += random.choice([0, 1])
            for _ in range(n):
                cat = random.choices(list(CATS), [c[3] for c in CATS.values()])[0]
                merchants, med, chw, _w = CATS[cat]
                ch = random.choices(list(chw), list(chw.values()))[0]
                amt = random.lognormvariate(math.log(med * mult ** 0.8 * SPEND_SCALE[seg]), 0.6)
                amt = max(20, min(amt, 60_000))
                if cat == "Cash Withdrawal":
                    amt = round(amt / 500) * 500 or 500
                online = ch in ("ONLINE",)
                city = "Online" if online else trip_days.get(day, home)
                add(aid, rand_ts(day), "DEBIT", cat, random.choice(merchants), ch, city, amt)

    # ---------------- fraud injection ----------------
    def acct_avg_spend(aid):
        v = [t["amount"] for t in txns[aid] if t["type"] == "DEBIT" and t["cat"] not in ("Rent/EMI",)]
        return sum(v) / len(v)

    fraud_accts = random.sample([a for a in accounts], k=int(len(accounts) * 0.12))
    for (aid, cid, atype, opened, ob, home, seg) in fraud_accts:
        for scenario in random.sample(["CARD_TESTING", "LARGE_ANOMALY", "GEO_IMPOSSIBLE"], k=random.choice([1, 1, 2])):
            day = random.choice(all_days[30:])
            avg = acct_avg_spend(aid)
            if scenario == "CARD_TESTING":
                t = dt.datetime.combine(day, dt.time()) + dt.timedelta(hours=random.randint(0, 5), minutes=random.randint(0, 59))
                for _ in range(random.randint(6, 8)):
                    add(aid, t, "DEBIT", "Shopping", random.choice(["QuickPay Gateway", "DigiMart Online"]),
                        "ONLINE", "Online", random.uniform(1, 499), "CARD_TESTING")
                    t += dt.timedelta(seconds=random.randint(30, 90))
                add(aid, t, "DEBIT", "Shopping", "TechZone Electronics", "ONLINE", "Online",
                    random.uniform(40_000, 120_000), "CARD_TESTING")
            elif scenario == "LARGE_ANOMALY":
                t = dt.datetime.combine(day, dt.time()) + dt.timedelta(hours=random.randint(1, 4), minutes=random.randint(0, 59))
                amt = min(max(avg * random.uniform(10, 20), 50_000), 250_000)
                add(aid, t, "DEBIT", "Shopping", "Unknown Merchant", "CARD",
                    random.choice([c for c in CITIES if c != home]), amt, "LARGE_ANOMALY")
            else:  # GEO_IMPOSSIBLE: home-city swipe, then another city 20 min later
                t = dt.datetime.combine(day, dt.time()) + dt.timedelta(hours=12, minutes=random.randint(0, 40))
                add(aid, t, "DEBIT", "Shopping", "Lifestyle", "CARD", home, random.uniform(1500, 6000))
                add(aid, t + dt.timedelta(minutes=random.randint(10, 25)), "DEBIT", "Shopping", "Lifestyle",
                    "CARD", random.choice([c for c in CITIES if c != home]), random.uniform(8000, 40_000),
                    "GEO_IMPOSSIBLE")

    # ---------------- balances + insert ----------------
    rows, labels = [], []
    flat = []
    for (aid, cid, atype, opened, ob, home, seg) in accounts:
        bal = ob
        for t in sorted(txns[aid], key=lambda x: x["ts"]):
            if t["type"] == "DEBIT" and t["fraud"] is None and t["amount"] > bal:
                continue  # insufficient funds: customer's own payment doesn't go through
            bal += t["amount"] if t["type"] == "CREDIT" else -t["amount"]
            t["aid"], t["bal"] = aid, round(bal, 2)
            flat.append(t)
    flat.sort(key=lambda x: (x["ts"], x["aid"]))
    for i, t in enumerate(flat, 1):
        rows.append((i, t["aid"], t["ts"].strftime("%Y-%m-%d %H:%M:%S"), t["type"], t["cat"],
                     t["merchant"], t["channel"], t["city"], t["amount"], t["bal"]))
        if t["fraud"]:
            labels.append((i, t["fraud"]))

    con.executemany("INSERT INTO customers VALUES (?,?,?,?,?)", customers)
    con.executemany("INSERT INTO accounts VALUES (?,?,?,?,?)", [a[:5] for a in accounts])
    con.executemany("INSERT INTO transactions VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    con.executemany("INSERT INTO fraud_labels VALUES (?,?)", labels)
    con.commit()
    print(f"customers={len(customers)} accounts={len(accounts)} transactions={len(rows)} fraud_txns={len(labels)}")
    con.close()


if __name__ == "__main__":
    main()
