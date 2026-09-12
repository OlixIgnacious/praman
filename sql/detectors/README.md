# Deterministic detectors — outlier/structuring scoring

The "one detector, two consumers" component from `architecture.md`: Stage 0 (`signal-query`, live NL questions) and Stage 2 (`assure-return`, draft-return validation against filing history) both need anomaly scoring, and it must be the *same* scoring logic reused, not two separately-tuned implementations that could quietly drift apart.

"Shared" here means literally shared: both views below call the same SQL UDF, `PRAMAN.CORE.ZSCORE`. The UDF is the actual detector; the two views are just its two applications at two different grains.

## Files (any order — independent of each other beyond the UDF)

1. `01_zscore_udf.sql` — `PRAMAN.CORE.ZSCORE(value, baseline_mean, baseline_stddev)`, the one formula both detectors call
2. `02_transaction_signals.sql` — `TRANSACTION_SIGNALS` view (Stage 0: structuring/velocity, daily grain per counterparty)
3. `03_gl_outlier_signals.sql` — `GL_OUTLIER_SIGNALS` view (Stage 2: draft-return-vs-history, monthly grain per `ACCOUNT_CODE`)

Run after `sql/ddl/` and the synthetic data load (both views query live tables); grants at the end of each script need `ANALYST_READ` to already exist (`sql/rbac/`).

## Design

**`TRANSACTION_SIGNALS`** (per `COUNTERPARTY_ID` × day): rolls up daily transaction count and amount, computes each day's z-score against that counterparty's own **trailing 90-day baseline** (`ROWS BETWEEN 90 PRECEDING AND 1 PRECEDING`, so the baseline never includes the day being scored), and flags `IS_CANDIDATE_STRUCTURING` when either the count or amount z-score is ≥ 3 *and* at least 30 days of baseline exist (a counterparty's first month is never flagged — there isn't enough history to know what "normal" looks like for them yet).

**`GL_OUTLIER_SIGNALS`** (per `ACCOUNT_CODE` × month): same method, applied to `GL_ENTRIES` instead of `TRANSACTIONS` — monthly total amount per account code, z-scored against a trailing 6-month baseline, flagged `IS_OUTLIER` at `|z| ≥ 3` with ≥3 months of baseline. This is the piece Stage 2 queries when validating a draft return line item against the firm's own filing history — `LINE_ITEM_MAP.SOURCE_COLUMN` values trace back to `ACCOUNT_CODE`s this view already scores.

Both use `ROWS BETWEEN n PRECEDING AND 1 PRECEDING` (never `CURRENT ROW`) for the baseline window — scoring a value against a baseline that includes itself understates how anomalous it is.

## What this deliberately does NOT do

**No "near-threshold clustering" heuristic** (e.g. "flag transactions parked just under IMPS's ₹5 lakh cap"), even though that's a textbook structuring pattern and the generator's own comments call out real channel caps. Adding it now would mean inventing a reporting-threshold rule not backed by anything in `RULE_CORPUS` — this project's whole design leans on citing real ingested rule text, not asserting thresholds from memory. Frequency/amount z-scoring against a counterparty's own history is a defensible, well-grounded signal without that; threshold-proximity scoring is a real gap, worth adding once an actual CTR/reporting-threshold circular is ingested, not before.

**No injected-case validation yet.** `INJECTED_CASES` (the eval answer key) is still unseeded — these views are the mechanism, not yet proven against known-true structuring/outlier cases. That's an Eval-phase task (`plan.md`, Days 15–17), not this one.

**Fixed z-score threshold of 3, not tunable per-account or learned.** Standard "3 sigma" convention, hardcoded once rather than parameterized — matches this project's general bias against config/abstraction the current scope doesn't need. Revisit only if the eval run (once it exists) shows the fixed threshold produces poor precision/recall for a specific `ERROR_TYPE`.
