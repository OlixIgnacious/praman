# Pending manual runs

## Done

Everything through Days 15–17's data/infrastructure work is deployed and verified live:
- Divergence disclosures (3 rows), audit evidence pack (`AUDIT_EVIDENCE_PACK`, 7 rows on verify), and the injected-cases catalogue (9/9 loaded, `GL_ENTRIES`/`TRANSACTIONS` counts exact, `structuring` case confirmed tripping `TRANSACTION_SIGNALS` live at `z=21.56`).
- `sql/load_synthetic_data.sql` now has `TRUNCATE` statements committed in the file itself — the run above used a manual `TRUNCATE` via `sql_execute` slightly ahead of that commit landing; the file is correct for any future re-run.

See `TRACKER.md`/`plan.md` for full detail.

## Nothing currently pending

Last piece of Days 15–17: the `EVAL_RESULTS` scoring harness (run Stage 0/2 against the loaded cases, write `MATCH_STATUS` rows, report precision/recall `GROUP BY ERROR_TYPE`). I'll build this next and queue its run command here once it's written.
