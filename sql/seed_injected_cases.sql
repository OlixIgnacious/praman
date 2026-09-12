-- Seed PRAMAN.EVAL.INJECTED_CASES with the 9-case catalogue generator/
-- generate_synthetic_data.py's inject_eval_cases() actually writes into
-- GL_ENTRIES/TRANSACTIONS (one CASE_ID per row here matches one
-- INJECTED_CASE_ID value there — keep both in sync if either changes, same
-- convention as anchors.py <-> sql/seed_line_item_map.sql).
--
-- One case per PRAMAN.EVAL.INJECTED_CASES.TYPE (sql/ddl/05_injected_cases.sql's
-- CHECK constraint), deliberately 1:1 — not more per type, since this is a
-- seed catalogue proving the mechanism works end to end, not a full eval
-- corpus (that's a later scale-up once Stage 0/2 are actually scored
-- against this).
--
-- No GRANT statement in this file, on purpose: per sql/rbac/README.md and
-- the isolation this table exists for, no Skill-runtime role (ANALYST_READ,
-- GOVERNANCE_WRITE, AUDIT_INSERT, OFFICER_SIGNOFF) is ever granted anything
-- on PRAMAN.EVAL. Run this as an admin role (ACCOUNTADMIN/SECURITYADMIN),
-- same as sql/ddl/00_database_and_schema.sql.

USE DATABASE PRAMAN;
USE SCHEMA EVAL;

INSERT INTO INJECTED_CASES
  (CASE_ID, TYPE, GROUND_TRUTH_LABEL, EXPECTED_STAGE, DESCRIPTION)
VALUES
  ('INJ-SIGN-01', 'sign',
   'ADVANCES_FUND entry recorded with a negative amount; fund-based advance ledger amounts must always be positive. A correct assure-return run should flag this as a sign error, cite the anomalous sign, and rank it above a plain value mismatch.',
   '2', 'One fund-based advance entry stored as a negative amount instead of positive.'),

  ('INJ-UNIT_SCALE-01', 'unit_scale',
   'ADVANCES_NONFUND entry recorded roughly 1000x larger than a comparable entry -- consistent with a units error (e.g. entered in paise or thousands instead of rupees). Should trip GL_OUTLIER_SIGNALS for its ACCOUNT_CODE/month and be flagged as a scale anomaly, not accepted as a legitimate large exposure.',
   '2', 'One non-fund advance entry scaled ~1000x too large versus its peer entries.'),

  ('INJ-DOUBLE_COUNTING-01', 'double_counting',
   'The same economic event (identical COUNTERPARTY_ID, POSITION_ID, ACCOUNT_CODE, and AMOUNT as an existing clean entry) posted a second time on a different POSTING_DATE. A correct run should identify this as a duplicate posting, not two independent advances.',
   '2', 'One fund-based advance entry duplicates an existing clean entry''s counterparty/position/amount, posted again on a different date.'),

  ('INJ-CLASSIFICATION-01', 'classification',
   'An exposure booked to NPA_DOUBTFUL_1 that, by amount and profile, matches the Substandard bucket''s ageing criteria -- a misclassification within the NPA buckets, not a change in the underlying exposure. Should be flagged as a classification error against LINE_ITEM_MAP''s PILLAR3.NPA_CLASS.* mappings, once those are approved.',
   '2', 'One NPA entry booked to the wrong ageing/classification bucket.'),

  ('INJ-TIMING-01', 'timing',
   'A fund-based advance entry posted with POSTING_DATE after the AS_OF_DATE reporting cutoff (2026-06-30) it is nonetheless included in this period''s ledger -- a cut-off/timing error; it belongs in the next reporting period. Should be flagged as a timing discrepancy, not included in this period''s computed line-item value.',
   '2', 'One fund-based advance entry posted after the reporting period''s cutoff date.'),

  ('INJ-STALE_REF-01', 'stale_ref',
   'A fund-based advance entry references a POSITION_ID that does not exist in POSITIONS -- an orphaned/stale reference, e.g. from a position that was closed or superseded without the GL entry being corrected. Should be flagged as a referential-integrity issue, not silently included in aggregates keyed off POSITION_ID.',
   '2', 'One GL entry references a POSITION_ID with no corresponding row in POSITIONS.'),

  ('INJ-DEFENSIBLE_INTERPRETATION-01', 'defensible_interpretation',
   'A non-fund instrument (originally a guarantee) booked as ADVANCES_FUND rather than ADVANCES_NONFUND -- consistent with a defensible interpretation that a drawn/invoked guarantee becomes a funded exposure. Not a clear error. Expected assure-return behavior: note the ambiguity and abstain rather than flag as a false positive.',
   '2', 'One entry booked under a defensible-but-debatable classification interpretation, not an outright error.'),

  ('INJ-CORRECT_BUT_ANOMALOUS-01', 'correct_but_anomalous',
   'A large, correctly-booked one-off fund-based advance (roughly 20x a typical entry for its counterparty) -- statistically anomalous versus GL_OUTLIER_SIGNALS'' baseline, but legitimate and correctly recorded. Expected assure-return behavior: note it may surface as a statistical outlier without treating that as evidence of an actual defect.',
   '2', 'One legitimately large, correctly-booked entry that is statistically anomalous but not an error.'),

  ('INJ-STRUCTURING-01', 'structuring',
   'A single counterparty (with an established >=30-day transaction baseline) receives a burst of ~15 same-day cash transactions, each just under a round reporting-relevant threshold, on one day near the end of the observation window. Designed to trip TRANSACTION_SIGNALS'' |z| >= 3 structuring/velocity threshold. Expected signal-query behavior: flag for compliance review, never present as a confirmed structuring verdict.',
   '0', 'One counterparty shows a same-day transaction-count/amount spike consistent with structuring.');
