"""Integrity checks on the disclosed figures transcribed from the Pillar 3 PDF."""

import pytest
from generator.anchors import (
    INDUSTRY_EXPOSURE,
    INDUSTRY_NPA,
    NPA_CLASSIFICATION_SHARE,
    RISK_WEIGHT_BUCKET_SHARE,
)


def test_exposure_row_count():
    assert len(INDUSTRY_EXPOSURE) == 42


def test_npa_row_count():
    assert len(INDUSTRY_NPA) == 42


def test_exposure_fund_total():
    total = sum(row[1] for row in INDUSTRY_EXPOSURE)
    assert total == pytest.approx(34_159_908.2, abs=0.5)


def test_exposure_nonfund_total():
    total = sum(row[2] for row in INDUSTRY_EXPOSURE)
    assert total == pytest.approx(3_196_716.8, abs=0.1)


def test_npa_gross_total():
    total = sum(row[1] for row in INDUSTRY_NPA)
    assert total == pytest.approx(384_786.7, abs=0.1)


def test_npa_provisions_total():
    total = sum(row[2] for row in INDUSTRY_NPA)
    assert total == pytest.approx(248_800.4, abs=0.1)


def test_industry_names_match():
    exposure_names = [row[0] for row in INDUSTRY_EXPOSURE]
    npa_names = [row[0] for row in INDUSTRY_NPA]
    assert exposure_names == npa_names


def test_no_negative_exposure():
    for name, fund, nonfund in INDUSTRY_EXPOSURE:
        assert fund >= 0, f"{name} has negative fund exposure"
        assert nonfund >= 0, f"{name} has negative non-fund exposure"


def test_no_negative_npa():
    for name, gross, prov in INDUSTRY_NPA:
        assert gross >= 0, f"{name} has negative gross NPA"
        assert prov >= 0, f"{name} has negative provisions"


def test_provisions_le_gross_npa():
    for name, gross, prov in INDUSTRY_NPA:
        assert prov <= gross + 0.01, f"{name}: provisions {prov} > gross NPA {gross}"


def test_npa_classification_share_sums_to_one():
    assert sum(NPA_CLASSIFICATION_SHARE.values()) == pytest.approx(1.0, abs=1e-9)


def test_npa_classification_numerators_sum():
    total_npa = 384_786.7
    numerator_sum = sum(s * total_npa for s in NPA_CLASSIFICATION_SHARE.values())
    assert numerator_sum == pytest.approx(total_npa, abs=0.1)


def test_risk_weight_share_sums_to_one():
    assert sum(RISK_WEIGHT_BUCKET_SHARE.values()) == pytest.approx(1.0, abs=1e-9)


def test_risk_weight_numerators_sum():
    total_exposure = 37_356_625.3
    numerator_sum = sum(s * total_exposure for s in RISK_WEIGHT_BUCKET_SHARE.values())
    assert numerator_sum == pytest.approx(total_exposure, abs=0.1)
