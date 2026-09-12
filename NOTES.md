# Pending manual runs

## Done

Everything through Days 15–17's data/infrastructure — divergence disclosures, audit evidence pack, injected-cases catalogue — is deployed and verified live. See `TRACKER.md`/`plan.md` for detail.

## Pending — enable the eval pass, then run it

### 1. Redeploy `SP_WRITE_AUDIT_LOG` with the `IS_EVAL` fix

```
cortex -c reg_reporting_agent "Read and execute sql/procedures/01_sp_write_audit_log.sql."
```

Adds a 9th parameter (`IS_EVAL`) so eval traffic can be tagged `AUDIT_LOG.IS_EVAL=TRUE` instead of always `FALSE`. This drops the old 8-arg procedure overload first (Snowflake treats a different argument count as a new overload, not a replacement) and runs as `ACCOUNTADMIN` rather than `SECURITYADMIN` — dropping an object already owned by `AUDIT_INSERT` is a different privilege question than the original ownership transfer. See `sql/procedures/README.md` for the full reasoning.

### 2. Redeploy `SIGNAL_ASSURE_AGENT` with the `[EVAL]` marker

```
cortex -c reg_reporting_agent "Using the agent-studio skill, redeploy the agent spec at cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml to PRAMAN.CORE.SIGNAL_ASSURE_AGENT."
```

Adds `is_eval` (required, per the "agent drops optional args" lesson) to the `write_audit_log` tool, and an orchestration rule: a question prefixed `[EVAL]` is a held-out eval case, answered exactly as normal except `is_eval="TRUE"` instead of `"FALSE"`.

**Quick sanity check before running the full eval pass:** ask the agent one plain (non-`[EVAL]`) question, confirm it still works and writes `IS_EVAL=FALSE` as before — the two changes above touch the exact same tool call every real question already depends on.

### 3. Run the eval pass

Full runbook: `eval/run_eval.md` — 12 held-out cases (9 `INJECTED_CASES` + 3 built from the real `DIVERGENCE_DISCLOSURES` data, calibrated to real-world materiality thresholds), each with the exact question to ask, expected behavior, and the `EVAL_RESULTS` insert template. Run as an admin role for the `EVAL_RESULTS` writes (no Skill-runtime role has `PRAMAN.EVAL` access).

Final report, once all 12 are scored:
```sql
SELECT ERROR_TYPE, MATCH_STATUS, COUNT(*) AS N
FROM PRAMAN.EVAL.EVAL_RESULTS
GROUP BY ERROR_TYPE, MATCH_STATUS
ORDER BY ERROR_TYPE, MATCH_STATUS;
```

Tell me the results (especially anything that scored `false_positive`/`false_negative` unexpectedly) and I'll close out Days 15–17.
