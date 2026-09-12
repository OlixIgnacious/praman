# Pending manual runs

## Done

Everything through eval v2 (11/12) is deployed and verified live. See `eval/results.md`, `TRACKER.md`/`plan.md`.

## Pending — fix #5: the `correct_but_anomalous` false positive

Real detector work, not a wording tweak this time: `CREDIT_EXPOSURE_SV` gained a per-counterparty, per-`ACCOUNT_CODE` scale-anomaly baseline (`entry_scale_zscore`/`is_entry_scale_outlier`, reusing the shared `ZSCORE` UDF — a third consumer of it, alongside `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS`), plus an orchestration change to cross-reference `CONCENTRATION_GROUP` before calling a scale outlier a likely error.

### 1. Redeploy `CREDIT_EXPOSURE_SV`

This one has a real dependency now — `entry_scale_zscore` calls `ZSCORE`, so the detector UDF must exist first (it already does, but if you're ever running this from scratch, `sql/detectors/01_zscore_udf.sql` comes before this file). This is a first-time combination of a window function + a custom UDF in a Semantic View metric, and every semantic view change in this project so far has needed at least one round of live-syntax correction (`LIKE ESCAPE`→`STARTSWITH`, `GRANT USAGE`→`GRANT SELECT`, the semi-additive metric fix) — leave the model at default rather than forcing the cheap tier here, in case it needs debugging:
```
cortex -c reg_reporting_agent "Read and execute sql/semantic_views/03_credit_exposure_sv.sql."
```

### 2. Redeploy `SIGNAL_ASSURE_AGENT`

Once #1 succeeds, a known workflow — cheaper model is fine:
```
cortex -m claude-sonnet-4-6 -c reg_reporting_agent "Using the agent-studio skill, redeploy the agent spec at cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml to PRAMAN.CORE.SIGNAL_ASSURE_AGENT."
```

### 3. Re-run `INJ-CORRECT_BUT_ANOMALOUS-01`

Same `[EVAL]`-prefixed question as before. Expect the agent to check `is_entry_scale_outlier` (with `counterparty_account_baseline_count >= 3`), see the entry's counterparty is `CONCENTRATION_GROUP = 'LARGE_EXPOSURE_TOP5PCT'` (worth confirming `GL-000322`'s counterparty actually is in that group — if it isn't, the fix's premise doesn't hold and needs a re-think, not just a re-test), and correctly note it as a statistical outlier for a known large-exposure counterparty rather than a probable error.

### 4. Quick regression spot-check

One `[EVAL]` question that already passed (`INJ-SIGN-01` or `INJ-STALE_REF-01`) — confirm the new `CREDIT_EXPOSURE_SV` columns didn't break anything already working.

### 5. Write the `EVAL_RESULTS` row and re-report

Same template as `eval/run_eval.md`, new `EVAL_ID` (e.g. `EVR-005-v3`). Then:
```sql
SELECT ERROR_TYPE, MATCH_STATUS, COUNT(*) AS N
FROM PRAMAN.EVAL.EVAL_RESULTS
GROUP BY ERROR_TYPE, MATCH_STATUS
ORDER BY ERROR_TYPE, MATCH_STATUS;
```

Tell me the result and I'll close this out in `eval/results.md` — 12/12 if it lands.
