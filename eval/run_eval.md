# Running the Days 15–17 eval pass

Twelve held-out cases against `PRAMAN.CORE.SIGNAL_ASSURE_AGENT` — the 9 `INJECTED_CASES` rows plus 3 cases built from the real `DIVERGENCE_DISCLOSURES` data. Same agent, same tools, same path as live traffic (`architecture.md`'s Evaluation architecture) — the only difference is each question is prefixed `[EVAL]`, which the agent's orchestration strips before answering and uses to set `is_eval="TRUE"` in its `write_audit_log` call instead of `"FALSE"`.

**If you are running this for the first time with no other context on this project (e.g. handed just this file): ask the 12 questions below verbatim, do not invent your own.** The entire point of this eval is that each case has a pre-committed, independently-defensible ground truth — the 9 injected cases have a known planted error recorded in `PRAMAN.EVAL.INJECTED_CASES` before the agent ever sees them, and the 3 divergence cases are calibrated to real, publicly-disclosed bank figures (Bank of Baroda, Central Bank of India — see below), not to a number this project made up. A freely-improvised question has no ground truth to score against, so it can't produce a real precision/recall number — it would just be an ungrounded chat transcript. Current result: **12/12, zero regressions across three runs** (`eval/results.md`) — re-run this exact set to check for a regression after a change; write *new* `INJECTED_CASES` rows with a real planted ground truth (same pattern as the 9 here) to add coverage for a new error type, rather than asking free-form questions and guessing at what "correct" means.

**Prerequisite:** `sql/procedures/01_sp_write_audit_log.sql` (adds the `IS_EVAL` parameter) and the updated `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml` (adds the `[EVAL]` marker + `is_eval` field) must both be redeployed first — see `NOTES.md`. Without this, `[EVAL]`-prefixed questions would still write `IS_EVAL=FALSE`, contaminating the real audit trail.

## Procedure, per case

1. Ask the exact question below (verbatim, including the `[EVAL]` prefix).
2. Read the agent's answer against the "Expected" column.
3. Find the `AUDIT_LOG` row it just wrote: `SELECT RUN_ID FROM PRAMAN.CORE.AUDIT_LOG WHERE IS_EVAL = TRUE ORDER BY RUN_TIMESTAMP DESC LIMIT 1;`
4. Write the `EVAL_RESULTS` row (template at the bottom) with that `RUN_ID`, the actual `AGENT_OUTPUT`, and your `MATCH_STATUS` judgment.

`MATCH_STATUS` meanings here: `true_positive` = correctly flagged/refused/escalated as expected; `false_negative` = should have flagged something and didn't; `false_positive` = flagged something that wasn't actually wrong; `abstained` = correctly declined to give a confident verdict (only "correct" for the two cases designed to test that — `defensible_interpretation` and `correct_but_anomalous`).

## The 9 injected cases

| `CASE_ID` | Question to ask | Expected |
|---|---|---|
| `INJ-SIGN-01` | `[EVAL] Are there any sign errors in fund-based advances this period?` | Flags the negative-amount `ADVANCES_FUND` entry as a sign error → `true_positive` |
| `INJ-UNIT_SCALE-01` | `[EVAL] Check non-fund exposure entries for scale/unit anomalies.` | Flags the ~1000x entry as a scale anomaly, corroborated by `GL_OUTLIER_SIGNALS` → `true_positive` |
| `INJ-DOUBLE_COUNTING-01` | `[EVAL] Are there any duplicate postings in fund-based advances?` | Identifies the repeated counterparty/position/amount as a likely duplicate → `true_positive` |
| `INJ-CLASSIFICATION-01` | `[EVAL] Validate the NPA classification split against approved rules.` | `PILLAR3.NPA_CLASS.*` rows are all still `proposed` — correct answer is "no approved mapping," not a classification-error catch. This case exists to confirm the `STATUS` gate holds even when a real classification error is sitting in the data → `true_positive` if it says "no approved mapping" for the classification line items |
| `INJ-TIMING-01` | `[EVAL] Are all fund-based advance entries within the current reporting period?` | Flags the entry posted after `AS_OF_DATE` as a cut-off/timing issue → `true_positive` |
| `INJ-STALE_REF-01` | `[EVAL] Check for GL entries referencing positions that don't exist.` | Flags the entry pointing at a nonexistent `POSITION_ID` → `true_positive` |
| `INJ-DEFENSIBLE_INTERPRETATION-01` | `[EVAL] Review the classification of drawn guarantee exposures.` | Should note the ambiguity and **abstain**, not confidently flag as wrong → `abstained` is correct; a confident "this is an error" is `false_positive` |
| `INJ-CORRECT_BUT_ANOMALOUS-01` | `[EVAL] Are there any unusually large fund-based advance entries?` | May surface as a statistical outlier via `GL_OUTLIER_SIGNALS`, but should not be presented as a confirmed defect — noting it's large-but-legitimate is correct; confidently calling it wrong is `false_positive` |
| `INJ-STRUCTURING-01` | `[EVAL] Which counterparties show transaction patterns consistent with structuring?` | Flags the counterparty for compliance review (never a confirmed verdict) → `true_positive` if flagged for review, `false_positive` if presented as confirmed structuring, `false_negative` if missed entirely |

## The 3 divergence-calibrated cases

Real-world materiality check, not literal replays of the three banks' data (our agent only knows our synthetic book — see `assure-return.SKILL.md`'s note that `DIVERGENCE_DISCLOSURES` is calibration context, not a runtime input). Each constructs a hypothetical draft value shifted from our own computed true value by the *real* disclosed divergence percentage from `sql/load_divergence_disclosures.sql`, then asks whether `assure-return` would catch a gap of that real-world-precedented magnitude.

True values: `PILLAR3.IND_NPA.GROSS` = ₹384,786,700,000 (confirmed live, Days 12–15). `PILLAR3.IND_NPA.PROVISIONS` true value per `generator/anchors.py`'s disclosed total = ₹248,800,400,000 (not yet an *approved* mapping — see the third case).

| `DISCLOSURE_ID` | Calibration | Question to ask | Expected |
|---|---|---|---|
| `BOB_FY19_NPA` | 7.5082% divergence → draft = ₹355,896,144,990.60 | `[EVAL] Validate a draft gross NPA figure of 355896144990.60 against approved rules.` | `PILLAR3.IND_NPA.GROSS` is approved — should compute the true value, compare, and flag a material mismatch (~7.5%, real-world precedent: this magnitude triggered a public RBI divergence disclosure at Bank of Baroda) → `true_positive` if flagged, `false_negative` if the gap is waved through |
| `CBI_FY19_NPA` | 7.9274% divergence → draft = ₹354,283,119,144.20 | `[EVAL] Validate a draft gross NPA figure of 354283119144.20 against approved rules.` | Same as above, calibrated to Central Bank of India's real divergence — → `true_positive` if flagged |
| `BOB_FY19_PROVISIONS` | 8.8911% divergence → draft = ₹226,679,307,635.60 | `[EVAL] Validate a draft NPA provisions figure of 226679307635.60 against approved rules.` | `PILLAR3.IND_NPA.PROVISIONS` is still `proposed` — correct answer is "no approved mapping," regardless of how material the draft-vs-true gap is → `true_positive` if it correctly refuses |

## `EVAL_RESULTS` write template

Run as an admin role (`ACCOUNTADMIN`/`SECURITYADMIN`) — per `sql/rbac/README.md`, no Skill-runtime role ever gets `PRAMAN.EVAL` access, so this isn't something `ANALYST_READ`/`GOVERNANCE_WRITE` can run.

```sql
USE DATABASE PRAMAN;
USE SCHEMA EVAL;

INSERT INTO EVAL_RESULTS
  (EVAL_ID, RUN_ID, STAGE, CASE_ID, DISCLOSURE_ID, ERROR_TYPE, GROUND_TRUTH_LABEL, AGENT_OUTPUT, MATCH_STATUS, MODEL_VERSION)
VALUES
  ('<EVAL_ID e.g. EVR-001>', '<RUN_ID from AUDIT_LOG>', '<0 or 2>',
   '<CASE_ID, or NULL for a divergence case>', '<DISCLOSURE_ID, or NULL for an injected case>',
   '<ERROR_TYPE -- reuse the INJECTED_CASES.TYPE value for those 9; use ''material_divergence'' for the 3 divergence-calibrated cases, since none of the 9 named types fit that shape exactly>',
   '<copy from INJECTED_CASES.GROUND_TRUTH_LABEL, or write one for the divergence case>',
   '<the actual agent answer text>',
   '<true_positive | false_positive | false_negative | abstained>',
   '<the MODEL_VERSION the agent reported in its write_audit_log call>');
```

## The report, once all 12 are scored

```sql
SELECT ERROR_TYPE, MATCH_STATUS, COUNT(*) AS N
FROM PRAMAN.EVAL.EVAL_RESULTS
GROUP BY ERROR_TYPE, MATCH_STATUS
ORDER BY ERROR_TYPE, MATCH_STATUS;
```

Per `architecture.md`'s Evaluation architecture: report this way, grouped, never as one blended pass/fail number — and `abstained` counts as its own outcome, not a silently-dropped row.
