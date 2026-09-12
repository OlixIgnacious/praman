"""Tests for the synthetic data generator — pure functions and reconciliation."""

from datetime import date

import numpy as np
import pandas as pd
import pytest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "generator"))

from generate_synthetic_data import (
    allocate_to_targets,
    counterparty_count,
    generate_counterparties,
    generate_gl_entries,
    generate_positions,
    generate_transactions,
    inject_eval_cases,
    rating_for_npa_rate,
    split_pareto,
    AS_OF,
    CHANNELS,
    CHANNEL_AMOUNT_RANGE,
    MILLION,
)
import anchors


@pytest.fixture
def rng():
    return np.random.default_rng(42)


# --- split_pareto ---

def test_split_pareto_sums_to_total(rng):
    result = split_pareto(1000.0, 10, rng)
    assert result.sum() == pytest.approx(1000.0)


def test_split_pareto_correct_length(rng):
    result = split_pareto(500.0, 7, rng)
    assert len(result) == 7


def test_split_pareto_all_positive(rng):
    result = split_pareto(100.0, 20, rng)
    assert (result > 0).all()


def test_split_pareto_single_element(rng):
    result = split_pareto(42.5, 1, rng)
    assert len(result) == 1
    assert result[0] == 42.5


def test_split_pareto_small_total(rng):
    result = split_pareto(0.01, 5, rng)
    assert result.sum() == pytest.approx(0.01)
    assert (result > 0).all()


# --- rating_for_npa_rate ---

def test_rating_zero_npa_rate(rng):
    rating = rating_for_npa_rate(0.0, rng)
    assert rating in ("AAA", "AA", "A")


def test_rating_low_npa_rate(rng):
    rating = rating_for_npa_rate(0.005, rng)
    assert rating in ("AAA", "AA", "A")


def test_rating_mid_npa_rate(rng):
    rating = rating_for_npa_rate(0.02, rng)
    assert rating in ("A", "BBB", "BB")


def test_rating_high_npa_rate(rng):
    rating = rating_for_npa_rate(0.5, rng)
    assert rating in ("BBB", "BB", "B")


def test_rating_at_one(rng):
    rating = rating_for_npa_rate(1.0, rng)
    assert rating in ("BBB", "BB", "B")


# --- counterparty_count ---

def test_counterparty_count_minimum():
    assert counterparty_count(0) == 3
    assert counterparty_count(-100) == 3


def test_counterparty_count_maximum():
    assert counterparty_count(1e12) <= 20


def test_counterparty_count_monotonic():
    counts = [counterparty_count(10**i) for i in range(1, 8)]
    for a, b in zip(counts, counts[1:]):
        assert b >= a


# --- allocate_to_targets ---

def test_allocate_preserves_per_row_sum(rng):
    entries = pd.DataFrame({"amt": [100.0, 200.0, 300.0]})
    targets = {"A": 250.0, "B": 150.0}
    frags = allocate_to_targets(entries, "amt", targets, rng)
    per_row = {}
    for f in frags:
        per_row.setdefault(f["index"], 0.0)
        per_row[f["index"]] += f["amount"]
    for i, row in entries.iterrows():
        assert per_row.get(i, 0.0) == pytest.approx(row["amt"], abs=1e-6)


def test_allocate_hits_target_totals(rng):
    entries = pd.DataFrame({"amt": [100.0, 200.0, 300.0, 50.0]})
    targets = {"X": 300.0, "Y": 200.0}
    frags = allocate_to_targets(entries, "amt", targets, rng)
    per_label = {}
    for f in frags:
        per_label.setdefault(f["label"], 0.0)
        per_label[f["label"]] += f["amount"]
    assert per_label.get("X", 0.0) == pytest.approx(300.0, abs=1e-6)
    assert per_label.get("Y", 0.0) == pytest.approx(200.0, abs=1e-6)


def test_allocate_no_negative_amounts(rng):
    entries = pd.DataFrame({"amt": [50.0, 100.0]})
    targets = {"A": 80.0}
    frags = allocate_to_targets(entries, "amt", targets, rng)
    for f in frags:
        assert f["amount"] >= 0


def test_allocate_single_entry_multiple_targets(rng):
    entries = pd.DataFrame({"amt": [500.0]})
    targets = {"A": 200.0, "B": 200.0}
    frags = allocate_to_targets(entries, "amt", targets, rng)
    total = sum(f["amount"] for f in frags)
    assert total == pytest.approx(500.0, abs=1e-6)


# --- Full pipeline reconciliation ---

@pytest.fixture(scope="module")
def generated_data():
    rng = np.random.default_rng(42)
    counterparties = generate_counterparties(rng)
    positions = generate_positions(counterparties, rng)
    gl_entries = generate_gl_entries(positions, counterparties, rng)
    return counterparties, positions, gl_entries


def test_counterparty_exposure_per_industry(generated_data):
    counterparties, _, _ = generated_data
    by_sector = counterparties.groupby("SECTOR")[["fund_amount", "nonfund_amount"]].sum() / MILLION
    for industry, fund_m, nonfund_m in anchors.INDUSTRY_EXPOSURE:
        got_fund = by_sector.loc[industry, "fund_amount"]
        got_nonfund = by_sector.loc[industry, "nonfund_amount"]
        assert got_fund == pytest.approx(fund_m, rel=1e-9), f"{industry} fund mismatch"
        assert got_nonfund == pytest.approx(nonfund_m, rel=1e-9), f"{industry} nonfund mismatch"


def test_gross_npa_total(generated_data):
    _, _, gl_entries = generated_data
    npa_mask = gl_entries["ACCOUNT_CODE"].str.startswith("NPA_") & (gl_entries["ACCOUNT_CODE"] != "NPA_PROVISION")
    total_npa = gl_entries.loc[npa_mask, "AMOUNT"].sum() / MILLION
    expected = sum(row[1] for row in anchors.INDUSTRY_NPA)
    assert total_npa == pytest.approx(expected, abs=0.1)


def test_npa_provisions_total(generated_data):
    _, _, gl_entries = generated_data
    prov = -gl_entries.loc[gl_entries["ACCOUNT_CODE"] == "NPA_PROVISION", "AMOUNT"].sum() / MILLION
    expected = sum(row[2] for row in anchors.INDUSTRY_NPA)
    assert prov == pytest.approx(expected, abs=0.5)


def test_npa_classification_split(generated_data):
    _, _, gl_entries = generated_data
    total_npa_m = sum(row[1] for row in anchors.INDUSTRY_NPA)
    for label, share in anchors.NPA_CLASSIFICATION_SHARE.items():
        code = f"NPA_{label}"
        got = gl_entries.loc[gl_entries["ACCOUNT_CODE"] == code, "AMOUNT"].sum() / MILLION
        expected = total_npa_m * share
        assert got == pytest.approx(expected, rel=0.01), f"{label}: {got} vs {expected}"


def test_all_positions_have_valid_counterparty(generated_data):
    counterparties, positions, _ = generated_data
    valid_ids = set(counterparties["COUNTERPARTY_ID"])
    assert set(positions["COUNTERPARTY_ID"]).issubset(valid_ids)


def test_all_gl_entries_have_valid_counterparty(generated_data):
    counterparties, _, gl_entries = generated_data
    valid_ids = set(counterparties["COUNTERPARTY_ID"])
    assert set(gl_entries["COUNTERPARTY_ID"]).issubset(valid_ids)


# --- generate_transactions ---
# Untested before this: the fourth generator output had no coverage at all.

@pytest.fixture(scope="module")
def transactions(generated_data):
    counterparties, _, _ = generated_data
    rng = np.random.default_rng(42)
    return generate_transactions(counterparties, rng)


def test_transactions_only_known_channels(transactions):
    assert set(transactions["CHANNEL"]).issubset(set(CHANNELS))


def test_transactions_non_rtgs_amounts_within_configured_range(transactions):
    # RTGS has no fixed upper bound (scales per-counterparty with exposure —
    # see test_transactions_rtgs_respects_minimum below), so it's excluded here.
    for channel, (lo, hi) in CHANNEL_AMOUNT_RANGE.items():
        if channel == "RTGS":
            continue
        subset = transactions[transactions["CHANNEL"] == channel]
        assert not subset.empty, f"no {channel} transactions generated at all"
        assert (subset["AMOUNT"] >= lo).all(), f"{channel} amount below configured minimum {lo}"
        assert (subset["AMOUNT"] <= hi).all(), f"{channel} amount above configured maximum {hi}"


def test_transactions_rtgs_respects_minimum(transactions):
    rtgs = transactions[transactions["CHANNEL"] == "RTGS"]
    assert not rtgs.empty
    assert (rtgs["AMOUNT"] >= 200_000).all()


def test_transactions_valid_counterparty_refs(generated_data, transactions):
    counterparties, _, _ = generated_data
    valid_ids = set(counterparties["COUNTERPARTY_ID"])
    assert set(transactions["COUNTERPARTY_ID"]).issubset(valid_ids)


def test_every_counterparty_has_at_least_one_transaction(generated_data, transactions):
    # n_txn is clipped to a minimum of 3 per counterparty (see generate_transactions),
    # so nobody should end up with zero transactions.
    counterparties, _, _ = generated_data
    all_ids = set(counterparties["COUNTERPARTY_ID"])
    txn_ids = set(transactions["COUNTERPARTY_ID"])
    assert txn_ids == all_ids


def test_transaction_ids_unique(transactions):
    assert transactions["TXN_ID"].is_unique


# --- inject_eval_cases ---
# The nine INJECTED_CASES.TYPE cases (sql/ddl/05_injected_cases.sql), layered
# on top of the already-reconciled book. These tests use their own fixture
# rather than touching `generated_data`/`transactions` above, so the original
# reconciliation tests keep validating the generator's clean-path functions
# directly, untouched.

ALL_CASE_IDS = {
    "INJ-SIGN-01", "INJ-UNIT_SCALE-01", "INJ-DOUBLE_COUNTING-01",
    "INJ-CLASSIFICATION-01", "INJ-TIMING-01", "INJ-STALE_REF-01",
    "INJ-DEFENSIBLE_INTERPRETATION-01", "INJ-CORRECT_BUT_ANOMALOUS-01",
    "INJ-STRUCTURING-01",
}


@pytest.fixture(scope="module")
def injected_data(generated_data):
    counterparties, positions, gl_entries = generated_data
    rng = np.random.default_rng(42)
    transactions = generate_transactions(counterparties, rng)
    gl_with_cases, txn_with_cases = inject_eval_cases(gl_entries, transactions, rng)
    return gl_with_cases, txn_with_cases


def _clean(df):
    return df[df["INJECTED_CASE_ID"] == ""]


def _case(df, case_id):
    rows = df[df["INJECTED_CASE_ID"] == case_id]
    assert len(rows) >= 1, f"no row found for {case_id}"
    return rows.iloc[0]


def test_injected_case_ids_present_and_unique(injected_data):
    gl_entries, transactions = injected_data
    gl_cases = set(gl_entries.loc[gl_entries["INJECTED_CASE_ID"] != "", "INJECTED_CASE_ID"])
    txn_cases = set(transactions.loc[transactions["INJECTED_CASE_ID"] != "", "INJECTED_CASE_ID"])
    assert gl_cases | txn_cases == ALL_CASE_IDS
    # Every case ID appears in exactly one of the two tables, not both.
    assert gl_cases.isdisjoint(txn_cases)


def test_injection_preserves_exact_reconciliation(injected_data):
    # The core promise: excluding injected rows reproduces today's exact
    # reconciled totals, byte for byte with the non-injected tests above.
    gl_entries, _ = injected_data
    clean = _clean(gl_entries)
    npa_mask = clean["ACCOUNT_CODE"].str.startswith("NPA_") & (clean["ACCOUNT_CODE"] != "NPA_PROVISION")
    total_npa = clean.loc[npa_mask, "AMOUNT"].sum() / MILLION
    expected_npa = sum(row[1] for row in anchors.INDUSTRY_NPA)
    assert total_npa == pytest.approx(expected_npa, abs=0.1)

    total_prov = -clean.loc[clean["ACCOUNT_CODE"] == "NPA_PROVISION", "AMOUNT"].sum() / MILLION
    expected_prov = sum(row[2] for row in anchors.INDUSTRY_NPA)
    assert total_prov == pytest.approx(expected_prov, abs=0.5)

    for label, share in anchors.NPA_CLASSIFICATION_SHARE.items():
        code = f"NPA_{label}"
        got = clean.loc[clean["ACCOUNT_CODE"] == code, "AMOUNT"].sum() / MILLION
        expected = expected_npa * share
        assert got == pytest.approx(expected, rel=0.01), f"{label}: {got} vs {expected}"


def test_sign_case_is_negative_advances_fund(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-SIGN-01")
    assert row["ACCOUNT_CODE"] == "ADVANCES_FUND"
    assert row["AMOUNT"] < 0


def test_unit_scale_case_is_1000x(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-UNIT_SCALE-01")
    assert row["ACCOUNT_CODE"] == "ADVANCES_NONFUND"
    assert row["AMOUNT"] >= 1_000_000  # a 1000x-scaled small entry lands well above normal position sizes


def test_double_counting_case_duplicates_an_existing_entry(injected_data):
    gl_entries, _ = injected_data
    dup = _case(gl_entries, "INJ-DOUBLE_COUNTING-01")
    match = _clean(gl_entries)
    match = match[
        (match["ACCOUNT_CODE"] == "ADVANCES_FUND")
        & (match["COUNTERPARTY_ID"] == dup["COUNTERPARTY_ID"])
        & (match["POSITION_ID"] == dup["POSITION_ID"])
        & (match["AMOUNT"] == dup["AMOUNT"])
    ]
    assert len(match) >= 1, "duplicate doesn't match any existing clean entry's amount/counterparty/position"


def test_classification_case_in_wrong_npa_bucket(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-CLASSIFICATION-01")
    assert row["ACCOUNT_CODE"] == "NPA_DOUBTFUL_1"


def test_timing_case_posted_after_as_of_date(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-TIMING-01")
    assert date.fromisoformat(row["POSTING_DATE"]) > AS_OF


def test_stale_ref_case_position_not_in_positions(injected_data, generated_data):
    _, positions, _ = generated_data
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-STALE_REF-01")
    assert row["POSITION_ID"] not in set(positions["POSITION_ID"])


def test_defensible_interpretation_case_exists(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-DEFENSIBLE_INTERPRETATION-01")
    assert row["ACCOUNT_CODE"] == "ADVANCES_FUND"
    assert row["AMOUNT"] > 0


def test_correct_but_anomalous_case_is_valid_and_large(injected_data):
    gl_entries, _ = injected_data
    row = _case(gl_entries, "INJ-CORRECT_BUT_ANOMALOUS-01")
    assert row["ACCOUNT_CODE"] == "ADVANCES_FUND"
    assert row["AMOUNT"] > 0


def test_structuring_case_creates_a_daily_spike(injected_data):
    _, transactions = injected_data
    inj = transactions[transactions["INJECTED_CASE_ID"] == "INJ-STRUCTURING-01"]
    assert len(inj) >= 10

    cp = inj["COUNTERPARTY_ID"].iloc[0]
    baseline = transactions[(transactions["COUNTERPARTY_ID"] == cp) & (transactions["INJECTED_CASE_ID"] == "")].copy()
    baseline["TXN_DATE"] = pd.to_datetime(baseline["TXN_TIMESTAMP"]).dt.date
    daily_counts = baseline.groupby("TXN_DATE").size()

    inject_date = pd.to_datetime(inj["TXN_TIMESTAMP"].iloc[0]).date()
    baseline_days_before = (daily_counts.index < inject_date).sum()
    assert baseline_days_before >= 30, "not enough baseline history before the injected day for TRANSACTION_SIGNALS to flag it"

    injected_day_total = daily_counts.get(inject_date, 0) + len(inj)
    avg_daily = daily_counts.mean()
    assert injected_day_total >= avg_daily * 3, "spike isn't large enough to be a plausible structural proxy for |z| >= 3"
