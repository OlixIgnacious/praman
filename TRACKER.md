# Build tracker — Praman

Quick status view across the full build, all phases in one place. Update the checkbox and the phase status line as work lands; `plan.md` still holds the folder layout and file-level detail, `architecture.md` holds the day-by-day rationale — this file is just "what's done vs. not," nothing more.

**Overall:** 7 of 8 phases done, 1 in progress. Currently in **Days 15–17** — catalogue/data/export all written, none yet run against Snowflake; `EVAL_RESULTS` scoring harness still to build.

---

## Day 1 — Decide & de-risk ✅ DONE
- [x] Pick jurisdiction (India/RBI) — Basel III Pillar 3 substitutes for gated CIMS returns; divergence disclosures substitute for amended-vs-original filing pairs
- [x] Provision Snowflake account + Coco CLI access, confirm region/residency (`SBOBPMM-YB05177`, `AWS_AP_SOUTHEAST_7`, upgraded to Enterprise Edition)
- [x] Spike: confirm native lineage tracing works (`cortex lineage` tested live on Enterprise)

## Days 2–3 — Real data sourcing ✅ DONE
- [x] Pull real documents for India: circulars (2), Pillar 3 disclosure (HDFC), divergence disclosures (3), penalty disclosures (2), AML/sanctions circulars (2) — tracked in `data-sources.md`
- [x] Pick the Pillar 3 disclosure anchoring the synthetic firm — HDFC Bank, quarter ending 2026-06-30

## Days 3–6 — Synthetic data + Snowflake foundation ✅ DONE
- [x] `generator/generate_synthetic_data.py` + `anchors.py` — 605 counterparties, 2,064 positions, 2,206 GL entries, 24,540 transactions, exactly reconciled to HDFC's disclosed figures
- [x] `sql/ddl/` — all 10 table DDLs written
- [x] Execute `sql/ddl/*.sql` against Snowflake — all 10 tables live in `PRAMAN.CORE` / `PRAMAN.EVAL`
- [x] Load `data/synthetic/` into Snowflake — row counts verified, gross NPA matches PDF exactly
- [x] `sql/rbac/` — roles + grants written and applied to Snowflake (`ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT` insert-only, `OFFICER_SIGNOFF`) — verified: no role has `UPDATE`/`DELETE` on `AUDIT_LOG`
- [x] Ingest circular 415 into `RULE_CORPUS` — 30 chunks loaded, `RULE_CORPUS_SEARCH` Cortex Search Service created and granted to `ANALYST_READ`
- [x] Seed `LINE_ITEM_MAP` — 9 rows loaded (`sql/seed_line_item_map.sql`), `STATUS='proposed'` pending governance approval

## Days 6–9 — Semantic layer, detectors, Skills ✅ DONE
- [x] `sql/semantic_views/` — `TRANSACTIONS_SV`, `POSITIONS_SV`, `CREDIT_EXPOSURE_SV` deployed to Snowflake (forked from `semantic-view-patterns`). Fixed during deployment: `LIKE ... ESCAPE` → `STARTSWITH(...)`, `GRANT USAGE ON SEMANTIC VIEW` → `GRANT SELECT ON SEMANTIC VIEW` (the correct privilege for this object type)
- [x] Deterministic detector logic — `ZSCORE` UDF + `TRANSACTION_SIGNALS` + `GL_OUTLIER_SIGNALS` deployed to Snowflake (`sql/detectors/`)
- [x] All four `SKILL.md` files written: `signal-query`, `circular-interpret`, `assure-return`, `narrative-draft`

## Days 9–12 — Backend + review UI ✅ DONE
- [x] `PRAMAN.CORE.SIGNAL_ASSURE_AGENT` — 5 tools, covers Stage 0 + Stage 2, live in CoWork ("Praman Signal + Assure"). 5/5 live test questions passed, `AUDIT_LOG` writing verified via `SP_WRITE_AUDIT_LOG`. `TRANSACTIONS_AGENT` spike dropped and cleaned up.
- [x] Three real Cortex Agent platform limitations found and fixed live (array-type args unsupported, `SPLIT()`/`ARRAY_CONSTRUCT()` invalid in `VALUES`, agent drops optional args) — see `plan.md` for detail

## Days 12–15 — Wire the four stages end-to-end ✅ DONE
- [x] Stage 0 live — covered by `SIGNAL_ASSURE_AGENT`'s Days 9–12 verification
- [x] Stage 2 live — happy path demoed after fixing a real bug: the agent had no tool to query `LINE_ITEM_MAP` at all, so its earlier "refusal" result was a hardcoded default, not a real `STATUS` check. Added `LINE_ITEM_MAP_SV` + `line_item_map_lookup` tool (mandatory first step in Stage 2 now); re-tested — correctly computed approved gross NPA with citation, correctly flagged the still-`proposed` classification sub-items in the same response
- [x] Stage 1 slice — `demos/stage1_circular_415_gap_analysis.md`: real gap analysis, no changes needed to the 9 seeded rows, real coverage gap named for other returns, one ambiguity flagged for escalation
- [x] Stage 3 walkthrough — `demos/stage3_lineage_walkthrough.md`: real live lineage trace confirms `GL_ENTRIES` → `CREDIT_EXPOSURE_SV` → `SIGNAL_ASSURE_AGENT` is fully traceable; applied to an explicitly-labeled illustrative scenario since no real injected break exists yet

## Days 15–17 — Eval 🔶 IN PROGRESS
- [~] `eval/` — `INJECTED_CASES` catalogue written (9 cases, one per `TYPE`, purely additive on top of the exactly-reconciled book — `test_injection_preserves_exact_reconciliation` proves it); **not yet run against Snowflake**
- [~] Divergence-disclosure ground truth (Bank of Baroda + Central Bank of India, YES Bank excluded for lack of a reliable base pair) written to `sql/load_divergence_disclosures.sql`; **not yet run**
- [~] Evidence-pack export (`AUDIT_EVIDENCE_PACK` view, citations resolved, granted to `GOVERNANCE_WRITE`) written to `sql/exports/01_audit_evidence_pack.sql`; **not yet run** — surfaced a real RBAC gap (no column links a sign-off row back to its run) as a flagged follow-up, not fixed
- [ ] `EVAL_RESULTS` scoring harness — actually running Stage 0/2 against the above and writing `MATCH_STATUS`/`GROUP BY ERROR_TYPE` results. Not started; needs the three items above loaded first.
- **Real bug caught in review, fixed before reaching Snowflake:** `sql/load_synthetic_data.sql` had no `TRUNCATE` before its `COPY INTO`s — re-running it against the regenerated (injected-case-carrying) CSVs would have duplicated every existing row, not just added the new ones. Fixed in the script itself.

## Days 17–18 — Rehearse & submit ⬜ NOT STARTED
- [ ] Dry-run the live path (Stage 0 + Stage 2) repeatedly
- [ ] Finalize pitch deck (penalty-disclosure impact framing)
- [ ] Submit
