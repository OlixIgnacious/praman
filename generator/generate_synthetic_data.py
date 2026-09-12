"""Synthetic firm generator — bottom-up from HDFC Bank's real Pillar 3 disclosure.

Per architecture.md's Data section: "take a real published return and synthesize a
GL, position set, and counterparty book that aggregates to those exact line items."

What's EXACTLY reconciled to the real PDF (data/raw/pillar3/, see anchors.py for page
refs), not approximated:
  - Industry-wise fund-based + non-fund-based exposure (40 industries)
  - Industry-wise gross NPA (40 industries)
  - Industry-wise NPA provisions (derived from each industry's real coverage ratio)
  - Book-wide NPA classification split (Substandard / Doubtful 1-3 / Loss)

What's a documented approximation, not a reconciled invariant:
  - POSITIONS.EXPOSURE_CLASS (Basel risk-weight bucket) — sampled at book-wide
    proportions (RISK_WEIGHT_BUCKET_SHARE), no per-industry disclosure exists to
    reconcile against.
  - TRANSACTIONS — no real anchor exists for transaction-level detail; channel mix
    and amounts are reasoned assumptions, not sourced.

What's deliberately wrong, not approximated: inject_eval_cases() layers nine
known-bad rows (GL_ENTRIES.INJECTED_CASE_ID / TRANSACTIONS.INJECTED_CASE_ID
set) on top of the reconciled book above, one per PRAMAN.EVAL.INJECTED_CASES
type (sql/ddl/05_injected_cases.sql). Purely additive — no clean row is
modified, so filtering WHERE INJECTED_CASE_ID = '' recovers the exact
reconciled totals above. See eval/README.md.

Amounts are stored in actual INR (anchors are in ₹ million — multiplied by 1e6),
so individual position/GL sizes read like a real core-banking ledger, not a
disclosure summary.

Usage: uv run python generator/generate_synthetic_data.py
Output: data/synthetic/{counterparties,positions,gl_entries,transactions}.csv
"""

from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
import anchors  # noqa: E402

SEED = 42
MILLION = 1_000_000
OUT_DIR = Path(__file__).parent.parent / "data" / "synthetic"
AS_OF = date.fromisoformat(anchors.AS_OF_DATE)

RATING_BANDS = [
    # (max_npa_rate, ratings pool, weights) — worse industry NPA rate -> worse ratings skew
    (0.005, ["AAA", "AA", "A"], [0.5, 0.35, 0.15]),
    (0.015, ["AA", "A", "BBB"], [0.3, 0.4, 0.3]),
    (0.03, ["A", "BBB", "BB"], [0.25, 0.45, 0.3]),
    (1.0, ["BBB", "BB", "B"], [0.2, 0.4, 0.4]),
]

FUND_INSTRUMENTS = ["Term Loan", "Cash Credit", "Investment - Debenture/Bond"]
FUND_WEIGHTS = [0.55, 0.30, 0.15]
NONFUND_INSTRUMENTS = [
    "Bank Guarantee",
    "Letter of Credit",
    "Derivative - FX Forward",
    "Derivative - Interest Rate Swap",
]
NONFUND_WEIGHTS = [0.40, 0.30, 0.20, 0.10]

NAME_SUFFIXES = ["Pvt Ltd", "Industries Ltd", "Enterprises", "Corp", "& Co", "Holdings Ltd"]

OVERSEAS_SHARE = 797356.4 / 37356625.3  # p.7, geographic distribution — applied as a sampling rate


def rating_for_npa_rate(npa_rate: float, rng: np.random.Generator) -> str:
    for max_rate, pool, weights in RATING_BANDS:
        if npa_rate <= max_rate:
            return rng.choice(pool, p=weights)
    return "B"


def split_pareto(total: float, n: int, rng: np.random.Generator) -> np.ndarray:
    """n shares of `total` with a realistic long tail (a few large, many small)."""
    if n == 1:
        return np.array([total])
    weights = rng.pareto(a=1.5, size=n) + 0.05
    return weights / weights.sum() * total


def counterparty_count(total_exposure_million: float) -> int:
    return int(np.clip(round(3 + 2 * np.log10(max(total_exposure_million, 1))), 3, 20))


def generate_counterparties(rng: np.random.Generator) -> pd.DataFrame:
    npa_by_industry = {row[0]: row for row in anchors.INDUSTRY_NPA}
    rows = []
    cp_seq = 0
    for industry, fund_m, nonfund_m in anchors.INDUSTRY_EXPOSURE:
        _, gross_npa_m, _ = npa_by_industry[industry]
        npa_rate = gross_npa_m / fund_m if fund_m > 0 else 0.0
        n = counterparty_count(fund_m + nonfund_m)
        fund_shares = split_pareto(fund_m, n, rng)
        nonfund_shares = split_pareto(nonfund_m, n, rng)
        suffixes = rng.choice(NAME_SUFFIXES, size=n)
        for i in range(n):
            cp_seq += 1
            rows.append(
                {
                    "COUNTERPARTY_ID": f"CP-{cp_seq:05d}",
                    "NAME": f"{industry.split(' - ')[0].split(' & ')[0][:24]} {suffixes[i]} {i + 1}",
                    "SECTOR": industry,
                    "JURISDICTION": "Overseas" if rng.random() < OVERSEAS_SHARE else "IN",
                    "RISK_RATING": rating_for_npa_rate(npa_rate, rng),
                    "fund_amount": fund_shares[i] * MILLION,
                    "nonfund_amount": nonfund_shares[i] * MILLION,
                }
            )
    df = pd.DataFrame(rows)
    total_exposure = df["fund_amount"] + df["nonfund_amount"]
    top5_cutoff = total_exposure.quantile(0.95)
    df["CONCENTRATION_GROUP"] = np.where(total_exposure >= top5_cutoff, "LARGE_EXPOSURE_TOP5PCT", "")
    df["CREATED_AT"] = anchors.AS_OF_DATE
    return df


def generate_positions(counterparties: pd.DataFrame, rng: np.random.Generator) -> pd.DataFrame:
    bucket_labels = list(anchors.RISK_WEIGHT_BUCKET_SHARE)
    bucket_weights = list(anchors.RISK_WEIGHT_BUCKET_SHARE.values())
    rows = []
    pos_seq = 0
    for cp in counterparties.itertuples():
        for book, total, instruments, weights in (
            ("fund", cp.fund_amount, FUND_INSTRUMENTS, FUND_WEIGHTS),
            ("nonfund", cp.nonfund_amount, NONFUND_INSTRUMENTS, NONFUND_WEIGHTS),
        ):
            if total <= 0:
                continue
            n = rng.integers(1, 4) if book == "fund" else rng.integers(1, 3)
            shares = split_pareto(total, n, rng)
            chosen = rng.choice(instruments, size=n, p=weights)
            buckets = rng.choice(bucket_labels, size=n, p=bucket_weights)
            for i in range(n):
                pos_seq += 1
                rows.append(
                    {
                        "POSITION_ID": f"POS-{pos_seq:06d}",
                        "INSTRUMENT_TYPE": chosen[i],
                        "NOTIONAL": round(shares[i], 2),
                        "CURRENCY": "INR",
                        "EXPOSURE_CLASS": buckets[i],
                        "COUNTERPARTY_ID": cp.COUNTERPARTY_ID,
                        "AS_OF_DATE": anchors.AS_OF_DATE,
                        "book": book,
                    }
                )
    return pd.DataFrame(rows)


def allocate_to_targets(
    entries: pd.DataFrame, amount_col: str, targets: dict[str, float], rng: np.random.Generator
) -> list[dict]:
    """Partition entries[amount_col] into fragments that exactly hit each label's
    target amount, splitting an entry across labels wherever a boundary falls
    inside it. Returns a flat list of {index, label, amount} fragments whose
    amounts sum, per original index, to that row's original amount exactly —
    so callers never need to reconstruct "how much of this row is left."
    Leftover amount once all targets are satisfied gets label "".
    """
    idx = entries.index.to_numpy().copy()
    rng.shuffle(idx)
    remaining_targets = dict(targets)
    label_order = [k for k in remaining_targets if remaining_targets[k] > 0]
    label_i = 0
    fragments = []
    for i in idx:
        amt = entries.at[i, amount_col]
        while amt > 1e-9:
            if label_i >= len(label_order):
                fragments.append({"index": i, "label": "", "amount": amt})
                amt = 0
                break
            label = label_order[label_i]
            need = remaining_targets[label]
            if need <= 1e-9:
                label_i += 1
                continue
            take = min(amt, need)
            fragments.append({"index": i, "label": label, "amount": take})
            remaining_targets[label] -= take
            amt -= take
    return fragments


def generate_gl_entries(
    positions: pd.DataFrame, counterparties: pd.DataFrame, rng: np.random.Generator
) -> pd.DataFrame:
    cp_sector = counterparties.set_index("COUNTERPARTY_ID")["SECTOR"]
    positions = positions.copy()
    positions["SECTOR"] = positions["COUNTERPARTY_ID"].map(cp_sector)

    entries = []
    entry_seq = 0
    npa_pool = []  # (amount, coverage_ratio, counterparty_id, position_id) for the global classification split

    npa_by_industry = {row[0]: row for row in anchors.INDUSTRY_NPA}

    for sector, group in positions[positions["book"] == "fund"].groupby("SECTOR"):
        _, gross_npa_m, provisions_m = npa_by_industry[sector]
        target = gross_npa_m * MILLION
        coverage_ratio = (provisions_m / gross_npa_m) if gross_npa_m > 0 else 0.0

        for frag in allocate_to_targets(group, "NOTIONAL", {"NPA": target}, rng):
            row = group.loc[frag["index"]]
            if frag["label"] == "NPA":
                npa_pool.append((frag["amount"], coverage_ratio, row.COUNTERPARTY_ID, row.POSITION_ID))
            elif frag["amount"] > 0:
                entry_seq += 1
                entries.append(
                    _gl_row(entry_seq, "ADVANCES_FUND", frag["amount"], row.COUNTERPARTY_ID, row.POSITION_ID, rng)
                )

    npa_df = pd.DataFrame(npa_pool, columns=["amount", "coverage_ratio", "COUNTERPARTY_ID", "POSITION_ID"])
    total_gross_npa = sum(row[1] for row in anchors.INDUSTRY_NPA) * MILLION
    total_npa_targets = {k: total_gross_npa * share for k, share in anchors.NPA_CLASSIFICATION_SHARE.items()}

    for frag in allocate_to_targets(npa_df, "amount", total_npa_targets, rng):
        row = npa_df.loc[frag["index"]]
        classification = frag["label"] or "SUBSTANDARD"  # "" leftover only from float rounding, negligible
        if frag["amount"] <= 0:
            continue
        entry_seq += 1
        entries.append(
            _gl_row(entry_seq, f"NPA_{classification}", frag["amount"], row.COUNTERPARTY_ID, row.POSITION_ID, rng)
        )
        entry_seq += 1
        entries.append(
            _gl_row(
                entry_seq, "NPA_PROVISION", -frag["amount"] * row.coverage_ratio,
                row.COUNTERPARTY_ID, row.POSITION_ID, rng, posting_date=AS_OF.isoformat(),
            )
        )

    # non-fund book: no NPA overlay (NPA classification applies to fund-based credit exposure)
    for row in positions[positions["book"] == "nonfund"].itertuples():
        entry_seq += 1
        entries.append(_gl_row(entry_seq, "ADVANCES_NONFUND", row.NOTIONAL, row.COUNTERPARTY_ID, row.POSITION_ID, rng))

    return pd.DataFrame(entries)


def _gl_row(seq, account_code, amount, counterparty_id, position_id, rng, posting_date=None, injected_case_id=""):
    if posting_date is None:
        offset_days = int(rng.integers(0, 3 * 365))
        posting_date = (AS_OF - timedelta(days=offset_days)).isoformat()
    return {
        "ENTRY_ID": f"GL-{seq:06d}",
        "ACCOUNT_CODE": account_code,
        "AMOUNT": round(amount, 2),
        "CURRENCY": "INR",
        "POSTING_DATE": posting_date,
        "COUNTERPARTY_ID": counterparty_id,
        "POSITION_ID": position_id,
        "INJECTED_CASE_ID": injected_case_id,
    }


CHANNELS = ["RTGS", "NEFT", "IMPS", "branch cash"]
CHANNEL_WEIGHTS_LARGE = [0.55, 0.30, 0.10, 0.05]  # large counterparties skew to RTGS
CHANNEL_WEIGHTS_SMALL = [0.05, 0.35, 0.40, 0.20]  # small counterparties skew to IMPS/cash

# Per-transaction amount ranges (INR) reflect real channel limits, not balance-sheet
# scale — IMPS is capped at ₹5 lakh in practice, NEFT/branch cash stay modest;
# RTGS has no regulatory cap (min ₹2 lakh) so its upper bound scales with the
# counterparty's own exposure instead of a fixed ceiling. This matters for Stage 0:
# structuring shows up as many transactions clustered just under a channel's real
# threshold, which only means something if the thresholds themselves are realistic.
CHANNEL_AMOUNT_RANGE = {
    "RTGS": (200_000, None),  # upper bound set per-counterparty below
    "NEFT": (10_000, 20_000_000),
    "IMPS": (1_000, 500_000),
    "branch cash": (500, 200_000),
}


def generate_transactions(counterparties: pd.DataFrame, rng: np.random.Generator) -> pd.DataFrame:
    total_exposure = counterparties["fund_amount"] + counterparties["nonfund_amount"]
    large_cutoff = total_exposure.quantile(0.8)
    rows = []
    txn_seq = 0
    for cp, exposure in zip(counterparties.itertuples(), total_exposure):
        n_txn = int(np.clip(np.log10(max(exposure, 1)) * 4, 3, 60))
        is_large = exposure >= large_cutoff
        weights = CHANNEL_WEIGHTS_LARGE if is_large else CHANNEL_WEIGHTS_SMALL
        rtgs_max = float(np.clip(exposure * 0.001, 2_000_000, 500_000_000))
        for _ in range(n_txn):
            txn_seq += 1
            offset_days = int(rng.integers(0, 90))
            offset_seconds = int(rng.integers(0, 86400))
            ts = AS_OF - timedelta(days=offset_days)
            channel = rng.choice(CHANNELS, p=weights)
            lo, hi = CHANNEL_AMOUNT_RANGE[channel]
            hi = rtgs_max if channel == "RTGS" else hi
            rows.append(
                {
                    "TXN_ID": f"TXN-{txn_seq:07d}",
                    "COUNTERPARTY_ID": cp.COUNTERPARTY_ID,
                    "AMOUNT": round(rng.uniform(lo, hi), 2),
                    "CURRENCY": "INR",
                    "TXN_TIMESTAMP": f"{ts.isoformat()}T{offset_seconds // 3600:02d}:{(offset_seconds % 3600) // 60:02d}:{offset_seconds % 60:02d}",
                    "CHANNEL": channel,
                    "INJECTED_CASE_ID": "",
                }
            )
    return pd.DataFrame(rows)


# Fixed catalogue of known-bad rows, one per PRAMAN.EVAL.INJECTED_CASES.TYPE
# (sql/ddl/05_injected_cases.sql's CHECK constraint — nine types, nine cases,
# deliberately 1:1). CASE_IDs and their GROUND_TRUTH_LABEL text are mirrored
# in sql/seed_injected_cases.sql — keep both in sync if either changes, same
# convention as anchors.py <-> sql/seed_line_item_map.sql. See eval/README.md
# for what each case represents and why.
def inject_eval_cases(
    gl_entries: pd.DataFrame, transactions: pd.DataFrame, rng: np.random.Generator
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Layer nine known-bad rows on top of the already-generated, already-
    reconciled book. Purely additive -- no existing row is modified, so the
    clean baseline's reconciliation to anchors.py is untouched by construction.
    Every injected row carries a real INJECTED_CASE_ID; every clean row keeps
    INJECTED_CASE_ID == "" -- filter on that to recover the exact reconciled
    totals (tests/test_generator.py's injected-case tests prove this holds,
    without touching the original reconciliation tests at all).
    """
    gl_entries = gl_entries.copy()
    transactions = transactions.copy()

    fund_rows = gl_entries[gl_entries["ACCOUNT_CODE"] == "ADVANCES_FUND"]
    nonfund_rows = gl_entries[gl_entries["ACCOUNT_CODE"] == "ADVANCES_NONFUND"]
    npa_sub_rows = gl_entries[gl_entries["ACCOUNT_CODE"] == "NPA_SUBSTANDARD"]

    gl_seq = len(gl_entries)
    new_gl_rows = []

    def next_gl_seq():
        nonlocal gl_seq
        gl_seq += 1
        return gl_seq

    # sign: a fund-based advance recorded with a negative amount. Ledger
    # amounts for ADVANCES_FUND should never be negative.
    a = fund_rows.iloc[0]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", -abs(a["AMOUNT"]) * 0.01,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-SIGN-01"))

    # unit_scale: a non-fund entry booked ~1000x too large -- e.g. entered in
    # paise/thousands instead of rupees.
    a = nonfund_rows.iloc[1]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_NONFUND", a["AMOUNT"] * 1000,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-UNIT_SCALE-01"))

    # double_counting: the same economic event (same counterparty, position,
    # account, amount) posted a second time on a different date.
    a = fund_rows.iloc[2]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", a["AMOUNT"],
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-DOUBLE_COUNTING-01"))

    # classification: an amount booked to the wrong NPA ageing bucket
    # (Substandard-sized exposure recorded as Doubtful_1).
    a = npa_sub_rows.iloc[0]
    new_gl_rows.append(_gl_row(next_gl_seq(), "NPA_DOUBTFUL_1", a["AMOUNT"] * 0.05,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-CLASSIFICATION-01"))

    # timing: entry posted after the AS_OF_DATE reporting cutoff it's being
    # booked into -- a cut-off error, belongs in next period's ledger.
    a = fund_rows.iloc[3]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", a["AMOUNT"] * 0.02,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                posting_date=(AS_OF + timedelta(days=5)).isoformat(),
                                injected_case_id="INJ-TIMING-01"))

    # stale_ref: entry referencing a POSITION_ID that does not exist in
    # POSITIONS -- orphaned/stale reference, e.g. from a closed position.
    a = fund_rows.iloc[4]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", a["AMOUNT"] * 0.01,
                                a["COUNTERPARTY_ID"], "POS-999999", rng,
                                injected_case_id="INJ-STALE_REF-01"))

    # defensible_interpretation: a drawn guarantee booked as a fund-based
    # advance rather than non-fund -- a genuine judgment call, not a clear
    # error (the bank's interpretation: funded once drawn).
    a = nonfund_rows.iloc[3]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", a["AMOUNT"] * 0.5,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-DEFENSIBLE_INTERPRETATION-01"))

    # correct_but_anomalous: a real, correctly-booked one-off large
    # disbursement -- statistically anomalous, not an error.
    a = fund_rows.iloc[5]
    new_gl_rows.append(_gl_row(next_gl_seq(), "ADVANCES_FUND", a["AMOUNT"] * 20,
                                a["COUNTERPARTY_ID"], a["POSITION_ID"], rng,
                                injected_case_id="INJ-CORRECT_BUT_ANOMALOUS-01"))

    gl_entries = pd.concat([gl_entries, pd.DataFrame(new_gl_rows)], ignore_index=True)

    # structuring: a burst of same-day transactions for an already-established
    # counterparty, sized to trip TRANSACTION_SIGNALS' |z| >= 3 threshold.
    # Injected close to AS_OF (not at the start of the 90-day window) so the
    # counterparty already has >=30 days of baseline history behind it --
    # TRANSACTION_SIGNALS never flags a counterparty with < 30 days observed.
    txn_counts = transactions["COUNTERPARTY_ID"].value_counts()
    inject_date = AS_OF - timedelta(days=2)
    target_cp = None
    for cp in txn_counts.index:
        cand = transactions[transactions["COUNTERPARTY_ID"] == cp]
        cand_dates = pd.to_datetime(cand["TXN_TIMESTAMP"]).dt.date
        if (cand_dates < inject_date).nunique() >= 30:
            target_cp = cp
            break
    if target_cp is None:
        target_cp = txn_counts.index[0]  # fallback: busiest counterparty regardless

    txn_seq = len(transactions)
    new_txn_rows = []
    for _ in range(15):
        txn_seq += 1
        offset_seconds = int(rng.integers(0, 86400))
        new_txn_rows.append(
            {
                "TXN_ID": f"TXN-{txn_seq:07d}",
                "COUNTERPARTY_ID": target_cp,
                "AMOUNT": round(rng.uniform(180_000, 200_000), 2),
                "CURRENCY": "INR",
                "TXN_TIMESTAMP": f"{inject_date.isoformat()}T{offset_seconds // 3600:02d}:{(offset_seconds % 3600) // 60:02d}:{offset_seconds % 60:02d}",
                "CHANNEL": "branch cash",
                "INJECTED_CASE_ID": "INJ-STRUCTURING-01",
            }
        )
    transactions = pd.concat([transactions, pd.DataFrame(new_txn_rows)], ignore_index=True)

    return gl_entries, transactions


def verify(counterparties: pd.DataFrame, gl_entries: pd.DataFrame) -> None:
    print("\n=== Reconciliation against real disclosed figures (₹ million) ===")

    by_sector = counterparties.groupby("SECTOR")[["fund_amount", "nonfund_amount"]].sum() / MILLION
    max_delta_pct = 0.0
    for industry, fund_m, nonfund_m in anchors.INDUSTRY_EXPOSURE:
        got_fund = by_sector.loc[industry, "fund_amount"]
        got_nonfund = by_sector.loc[industry, "nonfund_amount"]
        d1 = abs(got_fund - fund_m) / fund_m * 100 if fund_m else 0
        d2 = abs(got_nonfund - nonfund_m) / nonfund_m * 100 if nonfund_m else 0
        max_delta_pct = max(max_delta_pct, d1, d2)
    print(f"Industry exposure (fund + non-fund, 40 industries): max delta {max_delta_pct:.6f}% (float rounding only)")

    npa_entries = gl_entries[gl_entries["ACCOUNT_CODE"].str.startswith("NPA_") & (gl_entries["ACCOUNT_CODE"] != "NPA_PROVISION")]
    total_npa = npa_entries["AMOUNT"].sum() / MILLION
    target_total_npa = sum(row[1] for row in anchors.INDUSTRY_NPA)
    print(f"Gross NPA total: generated {total_npa:,.1f}  vs  disclosed {target_total_npa:,.1f}  (delta {abs(total_npa - target_total_npa):.4f})")

    prov_entries = gl_entries[gl_entries["ACCOUNT_CODE"] == "NPA_PROVISION"]
    total_prov = -prov_entries["AMOUNT"].sum() / MILLION
    target_total_prov = sum(row[2] for row in anchors.INDUSTRY_NPA)
    print(f"NPA provisions total: generated {total_prov:,.1f}  vs  disclosed {target_total_prov:,.1f}  (delta {abs(total_prov - target_total_prov):.4f})")

    print("\nNPA classification split (generated vs disclosed):")
    for label, share in anchors.NPA_CLASSIFICATION_SHARE.items():
        code = f"NPA_{label}"
        got = gl_entries[gl_entries["ACCOUNT_CODE"] == code]["AMOUNT"].sum() / MILLION
        target = target_total_npa * share
        print(f"  {label:12s} generated {got:>10,.1f}  vs  disclosed {target:>10,.1f}")

    total_fund_exposure = counterparties["fund_amount"].sum() / MILLION
    print(f"\nTotal fund-based exposure: {total_fund_exposure:,.1f} (disclosed: {sum(r[1] for r in anchors.INDUSTRY_EXPOSURE):,.1f})")
    print("EXPOSURE_CLASS (risk-weight buckets) and TRANSACTIONS are documented approximations, not reconciled — see module docstring.")


def main() -> None:
    rng = np.random.default_rng(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Generating counterparties...")
    counterparties = generate_counterparties(rng)
    print(f"  {len(counterparties)} counterparties across {counterparties['SECTOR'].nunique()} sectors")

    print("Generating positions...")
    positions = generate_positions(counterparties, rng)
    print(f"  {len(positions)} positions")

    print("Generating GL entries (with exact NPA reconciliation)...")
    gl_entries = generate_gl_entries(positions, counterparties, rng)
    print(f"  {len(gl_entries)} GL entries")

    print("Generating transactions...")
    transactions = generate_transactions(counterparties, rng)
    print(f"  {len(transactions)} transactions")

    verify(counterparties, gl_entries)

    print("\nInjecting eval catalogue (9 known-bad rows, one per INJECTED_CASES type)...")
    gl_entries, transactions = inject_eval_cases(gl_entries, transactions, rng)
    n_injected_gl = (gl_entries["INJECTED_CASE_ID"] != "").sum()
    n_injected_txn = (transactions["INJECTED_CASE_ID"] != "").sum()
    print(f"  +{n_injected_gl} injected GL entries, +{n_injected_txn} injected transactions")

    counterparties_out = counterparties.drop(columns=["fund_amount", "nonfund_amount"])
    positions_out = positions.drop(columns=["book", "SECTOR"], errors="ignore")
    gl_entries_out = gl_entries

    counterparties_out.to_csv(OUT_DIR / "counterparties.csv", index=False)
    positions_out.to_csv(OUT_DIR / "positions.csv", index=False)
    gl_entries_out.to_csv(OUT_DIR / "gl_entries.csv", index=False)
    transactions.to_csv(OUT_DIR / "transactions.csv", index=False)
    print(f"\nWritten to {OUT_DIR}/")


if __name__ == "__main__":
    main()
