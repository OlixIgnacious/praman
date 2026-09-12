# Stage 3 scripted walkthrough — lineage trace → root cause → narrative

The "Stage 3 scripted walkthrough" from `plan.md`'s Days 12–15. Two parts, kept clearly separate: the lineage trace below is **real, live output** from this project's actual Snowflake account; the "confirmed break" it's applied to is **illustrative** — the synthetic data is exactly reconciled to HDFC's disclosed figures (`tests/test_generator.py` enforces this), so there's no genuine data error to trace yet, and `INJECTED_CASES` (the real eval catalogue for this) is still unseeded (`plan.md`, Days 15–17). This walkthrough demonstrates the *mechanism* works end-to-end, not that a real bug was found.

## Part 1 — real lineage, run live

```
cortex lineage PRAMAN.CORE.GL_ENTRIES --direction downstream --distance 3 --tree
```

```
downstream of PRAMAN.CORE.GL_ENTRIES
├── PRAMAN.CORE.CREDIT_EXPOSURE_SV [SEMANTIC_VIEW]
│   └── PRAMAN.CORE.SIGNAL_ASSURE_AGENT [CORTEX_AGENT]
└── PRAMAN.CORE.GL_OUTLIER_SIGNALS [VIEW]
```

This is genuinely stronger evidence than the Day 1 spike (which only confirmed `cortex lineage` works at all, on a Snowflake sample table). It confirms native lineage tracks the **entire chain this project's architecture depends on**: source data (`GL_ENTRIES`) → governed semantic layer (`CREDIT_EXPOSURE_SV`) → the actual Cortex Agent that answers analyst questions (`SIGNAL_ASSURE_AGENT`) — and separately, the shared detector (`GL_OUTLIER_SIGNALS`). A report line item's answer in CoWork can be traced, object by object, all the way back to the ledger table that produced it, using nothing custom — exactly what `architecture.md`'s Day 1 note said would make Stage 3 "close to off-the-shelf."

One real limitation worth recording, found while running this: `cortex lineage` can't be queried starting *from* a Semantic View object directly (`--domain` only accepts `table`/`view`/`dataset`/`stage`/`column`/`dynamic_table`/`external_table`/`materialized_view` — `semantic_view` isn't a valid starting domain, only a node type that appears in a trace started from a table). Querying `CREDIT_EXPOSURE_SV` directly returns empty upstream/downstream; querying `GL_ENTRIES` and reading *its* downstream is what surfaces the semantic view. `narrative-draft` (or whatever eventually automates this) needs to trace from the base table, not the semantic view, when working backward from "which Semantic View did this answer come from."

## Part 2 — illustrative scenario applying the trace

**Confirmed signal (hypothetical):** Stage 2 flags that `CREDIT_EXPOSURE_SV.gross_npa` for the "Automobile & Auto Ancillary" sector looks anomalous — `GL_OUTLIER_SIGNALS` shows `IS_OUTLIER = TRUE` for the relevant `NPA_*` account codes in a recent month, corroborating a mismatch against a (hypothetically, once approved) expected value.

**Root cause walkthrough:**
1. **Trace lineage** (Part 1, real): `gross_npa` comes from `CREDIT_EXPOSURE_SV`, which reads `GL_ENTRIES` joined to `COUNTERPARTIES`.
2. **Narrow to the source rows** — lineage is object-level, not row-level, so the next step is a targeted query the trace justifies:
   ```sql
   SELECT g.ENTRY_ID, g.ACCOUNT_CODE, g.AMOUNT, g.POSTING_DATE, c.NAME, c.SECTOR
   FROM PRAMAN.CORE.GL_ENTRIES g
   JOIN PRAMAN.CORE.COUNTERPARTIES c ON g.COUNTERPARTY_ID = c.COUNTERPARTY_ID
   WHERE c.SECTOR = 'Automobile & Auto Ancillary'
     AND g.ACCOUNT_CODE LIKE 'NPA\_%' ESCAPE '\' AND g.ACCOUNT_CODE <> 'NPA_PROVISION'
   ORDER BY g.POSTING_DATE DESC;
   ```
3. **Rank candidates**: a single large, recently-posted entry outranks a diffuse spread of many small ones as the likely cause — per `narrative-draft.SKILL.md`'s ranking guidance. (Once `INJECTED_CASES` exists, a source row carrying a real `INJECTED_CASE_ID` would be the strongest candidate — that signal doesn't exist yet, so this step is judgment-based today.)
4. **Retrieve remediation basis**: `RULE_CORPUS_SEARCH` for the classification rule — in this project's current corpus, that's `RBI/DoS/2026-27/415#21` (the RAQ description), same honest caveat as `sql/seed_line_item_map.sql`: it names the return, not the classification methodology itself. A real remediation citation for *how* NPA classification should work would need a different circular ingested (not yet done).

**Draft narrative (illustrative, would need real figures + human sign-off before use):**

> During review of Q[X] asset-quality figures, the gross NPA balance for the Automobile & Auto Ancillary sector showed an anomalous month-over-month movement (z-score outside the ±3 threshold — see `GL_OUTLIER_SIGNALS`). Lineage tracing (`CREDIT_EXPOSURE_SV` → `GL_ENTRIES`) identified [N] entries posted in [month] as the primary contributors. [Root cause once identified]. Recommended remediation: [correction]. This figure is reported under the Return on Asset Quality (RAQ), per RBI/DoS/2026-27/415, para 21. **Draft only — pending review and sign-off.**

## What this walkthrough does and doesn't prove

**Proves:** the Stage 3 mechanism — native lineage tracing across the actual deployed objects, including the Cortex Agent itself — genuinely works, live, on real project infrastructure, not just on a Snowflake sample table.

**Doesn't prove:** that the detection/root-cause/remediation *content* is production-quality. That needs the real `INJECTED_CASES` catalogue (known-true breaks with ground-truth root causes) to actually score precision/recall against, per `architecture.md`'s Evaluation architecture — Days 15–17, not done yet. Flagging the gap rather than letting a clean illustrative walkthrough imply more than it should.
