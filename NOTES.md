# Pending manual runs

## Done

Everything through the full 7/12 eval pass (`eval/results.md`) is deployed and verified live.

## Pending — apply the 5 identified fixes, then re-test

### 1. Redeploy `CREDIT_EXPOSURE_SV` with row-level dimensions

```
cortex -c reg_reporting_agent "Read and execute sql/semantic_views/03_credit_exposure_sv.sql."
```

Adds `entry_id`/`account_code`/`amount`/`position_id` as queryable dimensions (previously only reachable inside aggregate `METRICS`) — fixes the `stale_ref` miss, where the agent couldn't see `POSITION_ID` at all.

### 2. Redeploy `SIGNAL_ASSURE_AGENT` with the Stage 2a/2b split

```
cortex -c reg_reporting_agent "Using the agent-studio skill, redeploy the agent spec at cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml to PRAMAN.CORE.SIGNAL_ASSURE_AGENT."
```

Splits Stage 2 into **2a** (line-item value validation — unchanged, still gated by `line_item_map_lookup`/`STATUS`) and **2b** (basic ledger integrity checks — sign, scale, duplicate, referential-integrity — no longer gated by `LINE_ITEM_MAP` approval, since a raw-data sanity check isn't "computing an approved line item's value"). Also fixes the duplicate-detection key (counterparty+position+account_code+amount, not date) and adds the "a statistical outlier isn't a presumptive defect" caveat.

### 3. Re-run the 5 previously-wrong cases (same `[EVAL]`-prefixed questions as `eval/run_eval.md`)

- `INJ-SIGN-01`, `INJ-UNIT_SCALE-01`, `INJ-DOUBLE_COUNTING-01`, `INJ-STALE_REF-01` — expect `true_positive` now (were `false_negative`)
- `INJ-CORRECT_BUT_ANOMALOUS-01` — expect the agent to note the anomaly without calling it a likely defect (were `false_positive`)

### 4. Regression-check 2 previously-passing cases

Confirm the 2a/2b split didn't break the governance gate itself:
- `INJ-CLASSIFICATION-01` — should still return "no approved mapping" (was `true_positive`)
- `BOB_FY19_NPA` (the material-divergence case) — should still compute and flag the ~7.5% gap (was `true_positive`)

### 5. Write the new `EVAL_RESULTS` rows and re-report

Same template as `eval/run_eval.md`, new `EVAL_ID`s (e.g. `EVR-00X-v2`) so both runs stay in history — don't overwrite the originals. Then:
```sql
SELECT ERROR_TYPE, MATCH_STATUS, COUNT(*) AS N
FROM PRAMAN.EVAL.EVAL_RESULTS
GROUP BY ERROR_TYPE, MATCH_STATUS
ORDER BY ERROR_TYPE, MATCH_STATUS;
```

Tell me the 5 (or 7) results and I'll write up the comparison in `eval/results.md` and close this out.
