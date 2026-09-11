"""Real, disclosed figures from data/raw/pillar3/HDFC_Bank_Basel_III_Pillar3_2026-06-30.pdf.

Everything here is transcribed directly from the PDF — page references noted per table.
This is the "real numbers at the top" half of the bottom-up synthesis (architecture.md,
Data section): the generator invents GL/position/counterparty plumbing that aggregates
to exactly these totals, so lineage from a report line item down to synthetic source
rows is known-true, not merely plausible.

Two tables reconcile exactly and anchor everything downstream:
- INDUSTRY_EXPOSURE: fund-based / non-fund-based credit exposure per industry (p.8)
- INDUSTRY_NPA: gross NPA / provisions per industry (p.11)
Both sum to the summary totals disclosed elsewhere in the same document (p.7, p.9).
"""

AS_OF_DATE = "2026-06-30"

# p.8, "Industry-wise distribution of exposures" (₹ million)
# (industry, fund_based, non_fund_based)
INDUSTRY_EXPOSURE = [
    ("Agriculture - Allied", 703431.5, 6495.4),
    ("Agriculture Produce - Trade", 200005.4, 15375.4),
    ("Agriculture Production - Food", 526487.6, 2420.6),
    ("Agriculture Production - Non food", 222841.8, 321.3),
    ("Animal Husbandry", 109883.4, 647.6),
    ("Automobile & Auto Ancillary", 598972.9, 60859.6),
    ("Banks", 646234.2, 169920.5),
    ("Business Services", 609709.2, 101991.9),
    ("Capital Market Intermediaries", 129284.0, 365516.6),
    ("Cement & Products", 95840.6, 64054.4),
    ("Chemical and Products", 290353.3, 68073.0),
    ("Coal & Petroleum Products", 405650.4, 197094.4),
    ("Consumer Durables", 216196.0, 39357.9),
    ("Consumer Loans", 10104645.1, 815.2),
    ("Consumer Services", 1204743.8, 62448.3),
    ("Drugs and Pharmaceuticals", 175293.3, 25524.3),
    ("Engineering", 559222.8, 271050.5),
    ("Fertilisers & Pesticides", 73015.6, 48867.3),
    ("Financial Institutions", 1190134.7, 71.9),
    ("Financial Intermediaries", 245220.8, 64331.7),
    ("FMCG & Personal Care", 95802.1, 4009.7),
    ("Food and Beverage", 876773.8, 63278.0),
    ("Gems and Jewellery", 234936.3, 13143.9),
    ("Housing Finance Companies", 524502.0, 501.8),
    ("Information Technology", 98724.0, 37466.3),
    ("Infrastructure Development", 589890.4, 464002.7),
    ("Iron and Steel", 693733.5, 132257.8),
    ("Mining and Minerals", 181978.7, 87169.1),
    ("NBFCs", 2095432.8, 4501.4),
    ("Non-ferrous Metals", 156600.8, 82193.2),
    ("Other Non-metalic Mineral Products", 100837.7, 19911.0),
    ("Paper, Printing and Stationery", 160892.0, 11864.2),
    ("Plastic & Products", 145580.0, 20066.8),
    ("Power", 903630.3, 142626.0),
    ("Real Estate & Property Services", 1275807.5, 88982.1),
    ("Retail Trade", 1233293.1, 76206.4),
    ("Road Transportation", 990368.7, 17769.5),
    ("Telecom", 288813.1, 21204.4),
    ("Textiles & Garments", 634458.2, 45767.7),
    ("Wholesale Trade - Industrial", 674801.9, 141957.7),
    ("Wholesale Trade - Non Industrial", 825626.9, 49515.3),
    ("Other Industries", 3070258.0, 107084.0),
]
# Disclosed total, p.8: fund 34,159,908.5 / non-fund 3,196,716.8 / total 37,356,625.3

# p.11, "Industry-wise distribution" NPA table (₹ million)
# (industry, gross_npa, provisions_for_npa)
INDUSTRY_NPA = [
    ("Agriculture - Allied", 21763.1, 14247.6),
    ("Agriculture Produce - Trade", 4983.2, 3682.2),
    ("Agriculture Production - Food", 37585.2, 26964.3),
    ("Agriculture Production - Non food", 11383.7, 8526.3),
    ("Animal Husbandry", 36366.7, 12118.2),
    ("Automobile & Auto Ancillary", 7036.6, 6138.2),
    ("Banks", 0.0, 0.0),
    ("Business Services", 4956.5, 3487.6),
    ("Capital Market Intermediaries", 3312.7, 3312.7),
    ("Cement & Products", 387.1, 195.9),
    ("Chemical and Products", 1877.1, 795.8),
    ("Coal & Petroleum Products", 1214.3, 690.0),
    ("Consumer Durables", 2304.2, 1546.2),
    ("Consumer Loans", 67323.8, 36225.4),
    ("Consumer Services", 8848.3, 7273.8),
    ("Drugs and Pharmaceuticals", 2680.9, 1947.2),
    ("Engineering", 8369.6, 7107.1),
    ("Fertilisers & Pesticides", 382.5, 109.2),
    ("Financial Institutions", 7.8, 2.6),
    ("Financial Intermediaries", 66.8, 27.0),
    ("FMCG & Personal Care", 919.6, 730.8),
    ("Food and Beverage", 19176.6, 14273.1),
    ("Gems and Jewellery", 1173.4, 941.2),
    ("Housing Finance Companies", 362.4, 362.4),
    ("Information Technology", 613.5, 498.6),
    ("Infrastructure Development", 5267.4, 3820.1),
    ("Iron and Steel", 4950.0, 3093.6),
    ("Mining and Minerals", 859.3, 499.6),
    ("NBFCs", 2044.8, 2036.7),
    ("Non-ferrous Metals", 1036.2, 675.7),
    ("Other Non-metalic Mineral Products", 544.6, 278.1),
    ("Paper, Printing and Stationery", 2136.5, 1374.4),
    ("Plastic & Products", 796.0, 397.9),
    ("Power", 6129.4, 5966.1),
    ("Real Estate & Property Services", 18096.3, 17576.1),
    ("Retail Trade", 23520.9, 14981.4),
    ("Road Transportation", 18856.7, 10368.9),
    ("Telecom", 166.3, 134.8),
    ("Textiles & Garments", 9587.3, 6433.8),
    ("Wholesale Trade - Industrial", 12822.7, 9280.2),
    ("Wholesale Trade - Non Industrial", 11982.5, 7433.1),
    ("Other Industries", 22894.2, 13246.5),
]
# Disclosed total, p.10: gross NPA 384,786.7 / provisions 248,800.4

# p.10, "Classification of Gross NPAs" (₹ million) — applied as a uniform ratio
# across every industry's NPA total below, since only the aggregate split is
# disclosed (not a per-industry breakdown). Documented approximation, not a
# reconciled invariant like the two tables above.
NPA_CLASSIFICATION_SHARE = {
    "SUBSTANDARD": 160610.5 / 384786.7,
    "DOUBTFUL_1": 83793.8 / 384786.7,
    "DOUBTFUL_2": 55050.2 / 384786.7,
    "DOUBTFUL_3": 50802.7 / 384786.7,
    "LOSS": 34529.5 / 384786.7,
}

# p.10, standardised-approach risk-weight buckets (₹ million) — applied as an
# overall book-level proportion when assigning POSITIONS.EXPOSURE_CLASS.
# Approximation, not reconciled per-industry (RBI doesn't disclose that cut).
RISK_WEIGHT_BUCKET_SHARE = {
    "BELOW_100": 17570067.8 / 37356625.3,
    "AT_100": 10256231.2 / 37356625.3,
    "ABOVE_100": 9427444.2 / 37356625.3,
    "DEDUCTED": 102882.1 / 37356625.3,
}
