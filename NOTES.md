# Pending manual runs

## Done

All of Days 9–12 and Days 12–15 — see `TRACKER.md`/`plan.md`. `LINE_ITEM_MAP_SV`'s DDL is now committed (`sql/semantic_views/04_line_item_map_sv.sql`), pulled from the live `GET_DDL` output.

## Pending — Days 15–17 (Eval)

### Divergence-disclosure ground truth

```
cortex -c reg_reporting_agent "Read and execute sql/load_divergence_disclosures.sql."
```

Loads 3 real rows (Bank of Baroda Gross NPA + Provisioning, Central Bank of India Gross NPA) into `PRAMAN.CORE.DIVERGENCE_DISCLOSURES`, per `sql/load_divergence_disclosures.sql`'s header comment for the `LINE_ITEM_ID` mapping rationale and why YES Bank's case was excluded. Independent of everything else queued here — no dependency order requirement with the other Days 15–17 items.

### Audit evidence-pack export

```
cortex -c reg_reporting_agent "Read and execute sql/exports/01_audit_evidence_pack.sql."
```

Creates `AUDIT_EVIDENCE_PACK` (a view over `AUDIT_LOG`, `IS_EVAL=TRUE` excluded, citations resolved against `RULE_CORPUS`) and grants `GOVERNANCE_WRITE` `SELECT` on it — the only role currently able to read `AUDIT_LOG` at all, in any form. See `sql/exports/01_audit_evidence_pack.sql`'s header comment for why `GOVERNANCE_WRITE` (imperfect fit, flagged) and a real schema gap around linking an officer sign-off row back to the run it signs off on (no column exists for that yet). Also independent of the other Days 15–17 items — no dependency order requirement.

Verify after running: `SELECT * FROM PRAMAN.CORE.AUDIT_EVIDENCE_PACK;` — should return one row per real (non-eval) invocation so far, with a `CITATIONS` array populated for Stage 2 rows and empty for Stage 0 rows.

### INJECTED_CASES catalogue + regenerated synthetic data

The synthetic CSVs changed (`data/synthetic/gl_entries.csv`/`transactions.csv` now carry 9 injected rows on top of the unchanged, exactly-reconciled clean book — see `eval/README.md`), so both the data reload and the new seed need to run, in this order:

```
cortex -c reg_reporting_agent "Read and execute sql/load_synthetic_data.sql, then sql/seed_injected_cases.sql, in order."
```

`sql/load_synthetic_data.sql` now `TRUNCATE`s all four `CORE` tables before reloading — a real bug caught during review: `COPY INTO` has no upsert semantics, so re-running the original PUT-then-`COPY INTO` script (no truncate) against a changed CSV would have inserted every row again, duplicating the whole clean book on top of itself rather than just adding the 8+15 new rows. Fixed in the script itself, not just noted here — safe to re-run now and in the future whenever `data/synthetic/*.csv` regenerates. `sql/seed_injected_cases.sql` inserts the matching 9 `PRAMAN.EVAL.INJECTED_CASES` rows — run as an admin role (no Skill-runtime role has `EVAL` access, so this can't run as `ANALYST_READ` etc.).

Worth checking after both land:
- `SELECT COUNT(*) FROM PRAMAN.CORE.COUNTERPARTIES;` → 605, `POSITIONS` → 2,064 (unchanged — `inject_eval_cases()` never touches these two tables; if either count differs, the truncate-then-reload didn't behave as expected)
- `SELECT COUNT(*) FROM PRAMAN.CORE.GL_ENTRIES;` → 2,214 (2,206 original + 8 injected); `WHERE INJECTED_CASE_ID != ''` → 8
- `SELECT COUNT(*) FROM PRAMAN.CORE.TRANSACTIONS;` → 24,555 (24,540 original + 15 injected); `WHERE INJECTED_CASE_ID != ''` → 15
- `SELECT * FROM PRAMAN.CORE.TRANSACTION_SIGNALS WHERE COUNTERPARTY_ID = (SELECT COUNTERPARTY_ID FROM PRAMAN.CORE.TRANSACTIONS WHERE INJECTED_CASE_ID = 'INJ-STRUCTURING-01' LIMIT 1) ORDER BY TXN_DATE DESC LIMIT 5;` → confirms the real SQL z-score actually trips `IS_CANDIDATE_STRUCTURING` (only checked structurally in Python so far, see `eval/README.md`'s last bullet)
- `SELECT COUNT(*) FROM PRAMAN.EVAL.INJECTED_CASES;` → 9

Independent of the other two Days 15–17 items above — no dependency order requirement between them, though this one internally requires its own two statements run in order (data reload before the seed references it conceptually, though there's no literal FK).
