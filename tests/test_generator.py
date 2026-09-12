"""Tests for the synthetic data generator — pure functions and reconciliation."""

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
    rating_for_npa_rate,
    split_pareto,
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
