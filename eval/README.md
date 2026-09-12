# Eval — INJECTED_CASES catalogue

The "eval/ — INJECTED_CASES catalogue" item from `plan.md`'s Days 15–17 phase. Nine known-bad rows, one per `TYPE` in `PRAMAN.EVAL.INJECTED_CASES`'s CHECK constraint (`sql/ddl/05_injected_cases.sql`) — a seed catalogue proving the eval mechanism works end to end, not a full eval corpus. Scaling to more cases per type is a later step once Stage 0/2 are actually being scored against this (`EVAL_RESULTS`, not built yet).

## Where the catalogue lives

- **`generator/generate_synthetic_data.py`'s `inject_eval_cases()`** — writes the actual bad rows into `data/synthetic/gl_entries.csv` and `data/synthetic/transactions.csv`, each carrying a real `INJECTED_CASE_ID`. Called from `main()` after the clean, exactly-reconciled book is generated and verified.
- **`sql/seed_injected_cases.sql`** — inserts the matching `CASE_ID`/`GROUND_TRUTH_LABEL`/`EXPECTED_STAGE` rows into `PRAMAN.EVAL.INJECTED_CASES`. The two files are manually kept in sync (same convention as `generator/anchors.py` ↔ `sql/seed_line_item_map.sql`) — if you add or change a case, update both.

## The one hard constraint this design preserves

`generator/generate_synthetic_data.py`'s whole premise is a synthetic book that **exactly reconciles** to HDFC's real disclosed Pillar 3 figures (enforced by `tests/test_generator.py`, some checks at `rel=1e-9`). Injected cases can't be allowed to break that. `inject_eval_cases()` is purely additive — it never modifies an existing clean row, only appends new ones with `INJECTED_CASE_ID` set. Filtering `WHERE INJECTED_CASE_ID = ''` on the output at any point reproduces the exact reconciled totals, byte for byte. `tests/test_generator.py`'s `test_injection_preserves_exact_reconciliation` proves this directly, using a separate `injected_data` fixture — the original reconciliation tests were left completely untouched rather than risk them.

## The nine cases

| `CASE_ID` | `TYPE` | `EXPECTED_STAGE` | What's wrong |
|---|---|---|---|
| `INJ-SIGN-01` | `sign` | 2 | Fund advance stored with a negative amount |
| `INJ-UNIT_SCALE-01` | `unit_scale` | 2 | Non-fund entry ~1000x too large |
| `INJ-DOUBLE_COUNTING-01` | `double_counting` | 2 | Same economic event posted twice, different date |
| `INJ-CLASSIFICATION-01` | `classification` | 2 | Exposure booked to the wrong NPA ageing bucket |
| `INJ-TIMING-01` | `timing` | 2 | Entry posted after the `AS_OF_DATE` reporting cutoff |
| `INJ-STALE_REF-01` | `stale_ref` | 2 | References a `POSITION_ID` that doesn't exist |
| `INJ-DEFENSIBLE_INTERPRETATION-01` | `defensible_interpretation` | 2 | Genuinely ambiguous classification call, not a clear error — expected to be abstained on, not flagged as a false positive |
| `INJ-CORRECT_BUT_ANOMALOUS-01` | `correct_but_anomalous` | 2 | Large but legitimate, correctly-booked entry — expected to surface as a statistical outlier without being treated as a real defect |
| `INJ-STRUCTURING-01` | `structuring` | 0 | Same-day transaction burst for one counterparty, sized to trip `TRANSACTION_SIGNALS`' `|z| >= 3` threshold |

Eight cases live in `GL_ENTRIES` (`EXPECTED_STAGE = '2'`, Stage 2/`assure-return` territory); one (`structuring`) lives in `TRANSACTIONS` (`EXPECTED_STAGE = '0'`, Stage 0/`signal-query` territory) — matching which table each stage actually reads.

## Why `defensible_interpretation` and `correct_but_anomalous` don't have a "right" flag

Per `architecture.md`'s Evaluation architecture, `abstained` is a first-class `MATCH_STATUS`, not a missing row. These two cases exist specifically to test that: a system that confidently flags every anomaly as an error, or confidently clears every ambiguous case, is failing at exactly what these two are designed to catch. A good `EVAL_RESULTS` scoring run should show these landing as `abstained` or correctly-not-flagged, not `false_positive`.

## Status

- **Deployed and verified.** All 9 cases loaded (`SELECT COUNT(*) FROM INJECTED_CASES` → 9), row counts confirmed exactly in `GL_ENTRIES`/`TRANSACTIONS`, and the `structuring` case's threshold is now confirmed at the SQL layer too, not just structurally in Python — it trips `TRANSACTION_SIGNALS` live at `z=21.56`, well past the `|z| >= 3` bar.
- **Eval pass run — 7/12 correct.** `run_eval.md`'s 12 cases (9 injected + 3 real-divergence-calibrated) scored against live `SIGNAL_ASSURE_AGENT` runs. Full breakdown, root causes, and fixes: **`results.md`**. Short version: the governance gate (the most compliance-critical behavior) scored 100%; all 4 misses have a diagnosed, non-architectural root cause (orchestration wording or one missing Semantic View column), not a design flaw.
