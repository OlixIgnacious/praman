# Eval results — 12/12 cases run, 7/12 correct

Per `eval/run_eval.md`, run live against `PRAMAN.CORE.SIGNAL_ASSURE_AGENT`. Reported grouped by `ERROR_TYPE`/`MATCH_STATUS`, never as one blended number, per `architecture.md`'s Evaluation architecture.

```sql
SELECT ERROR_TYPE, MATCH_STATUS, COUNT(*) AS N
FROM PRAMAN.EVAL.EVAL_RESULTS
GROUP BY ERROR_TYPE, MATCH_STATUS
ORDER BY ERROR_TYPE, MATCH_STATUS;
```

| `MATCH_STATUS` | Count | Cases |
|---|---|---|
| `true_positive` | 6 | `classification`, `material_divergence` ×3, `structuring`, `timing` |
| `abstained` | 1 | `defensible_interpretation` |
| `false_negative` | 4 | `sign`, `unit_scale`, `double_counting`, `stale_ref` |
| `false_positive` | 1 | `correct_but_anomalous` |

**7/12 correct** (6 `true_positive` + 1 correctly-`abstained`), 4 `false_negative`, 1 `false_positive`.

## What worked

- **The governance gate holds perfectly.** `classification` (unapproved), the provisions divergence case (unapproved), and `defensible_interpretation` were all correctly blocked/abstained on. This is the single most compliance-critical behavior in the whole system — a false approval here is the failure mode that actually causes regulatory harm — and it scored 100%.
- **Material-divergence detection: 3/3.** Both the ~7.5% and ~7.9% real-world-calibrated gaps were caught and flagged, matching the actual magnitude that triggered public RBI divergence disclosures at Bank of Baroda and Central Bank of India.
- **AML guardrail held.** The `structuring` case was flagged for compliance review, never presented as a confirmed verdict — exactly the behavior `signal-query.SKILL.md` and the agent's orchestration require.
- **Timing cutoff caught** — the post-`AS_OF_DATE` entry was correctly identified.

## What failed, and why — every miss has a diagnosed, non-architectural root cause

| Case | Failure | Root cause | Fix |
|---|---|---|---|
| `sign` | `false_negative` | Routed as Stage 2 → hit the governance gate on unapproved `PILLAR3.IND_EXPOSURE.FUND` → never actually scanned the raw data for the sign error | Approve the mapping, **or** give Stage 2 (or Stage 0) a basic-integrity-scan path that doesn't require `LINE_ITEM_MAP` approval — see below |
| `unit_scale` | `false_negative` | Same pattern — blocked on unapproved `PILLAR3.IND_EXPOSURE.NONFUND` | Same fix |
| `double_counting` | `false_negative` | Checked for duplicates on counterparty+date+amount; the injected duplicate has a *different* date (same counterparty+position+account_code+amount) — wrong dedup key, not a missed scan | Correct the orchestration's duplicate-detection key to counterparty+position+account_code+amount, not date |
| `stale_ref` | `false_negative` | `GL_ENTRIES.POSITION_ID` isn't exposed as a dimension in `CREDIT_EXPOSURE_SV` — the agent structurally cannot see the column it would need to check | Add `POSITION_ID` as a `CREDIT_EXPOSURE_SV` dimension, or a dedicated referential-integrity tool |
| `correct_but_anomalous` | `false_positive` | Agent called a legitimate large entry a "likely data-quality/posting issue" instead of noting it could be legitimate | Strengthen orchestration: a statistical outlier in a right-skewed book is not a presumptive error — note the anomaly, don't infer a defect without corroborating evidence |

**The four false negatives cluster into two distinct, both non-architectural, patterns:**

1. **Governance-gate overreach** (`sign`, `unit_scale`): the `STATUS='approved'` gate is doing exactly its job for *computing and reporting a governed line-item's value* — but it's also blocking basic ledger-integrity checks ("is this amount's sign valid for this account type") that arguably shouldn't need a `LINE_ITEM_MAP` approval at all, since they're sanity checks on raw data, not validation of an approved aggregation rule. Conflating the two inside one gate is the actual design gap.
2. **Missing surface area** (`double_counting`, `stale_ref`): the agent was asked to check something it either didn't have the right key for or couldn't see at all. Both fixable by exposing more/different data, not by rethinking the gate.

None of the five fixes require an architectural change — all are either an orchestration-instruction correction, a `LINE_ITEM_MAP` approval, or a one-column addition to an existing Semantic View.

## Deliberately not fixed yet

Fixing and re-running is real follow-up work, not done as part of this eval pass — this file records the score that direct testing actually produced, not a touched-up one. See `plan.md`'s Days 15–17 entry for the decision on whether/when to apply these fixes before submission.
