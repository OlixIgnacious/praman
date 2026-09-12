# Build tracker — Praman

Quick status view across the full build, all phases in one place. Update the checkbox and the phase status line as work lands; `plan.md` still holds the folder layout and file-level detail, `architecture.md` holds the day-by-day rationale — this file is just "what's done vs. not," nothing more.

**Overall:** 7 of 8 phases done. Days 15–17's eval went 7/12 → 11/12 → **12/12** across three runs, all 5 fixes landed clean with zero regressions at any point (`eval/results.md`). Only **Days 17–18 (rehearse & submit)** remains.

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

## Days 15–17 — Eval ✅ DONE
- [x] `eval/` — `INJECTED_CASES` catalogue deployed: 9/9 rows loaded, `GL_ENTRIES`/`TRANSACTIONS` counts confirmed exactly (2,214 / 24,555, 8 / 15 injected), and the `structuring` case genuinely trips `TRANSACTION_SIGNALS` live (`z=21.56` on 2026-06-28, `IS_CANDIDATE_STRUCTURING=TRUE` — the Python-only structural check is now confirmed at the SQL layer too)
- [x] Divergence-disclosure ground truth deployed — 3 rows loaded (Bank of Baroda ×2, Central Bank of India ×1; YES Bank excluded for lack of a reliable base pair)
- [x] Evidence-pack export deployed — `AUDIT_EVIDENCE_PACK` live, `GOVERNANCE_WRITE` granted, 7 rows returned on verify. RBAC gap (no sign-off-to-run linking column) remains a flagged follow-up, not fixed.
- [x] `EVAL_RESULTS` scoring harness — 12/12 cases run live, **7/12 correct** (v1). Governance gate (most compliance-critical behavior) scored 100%. All 4 misses root-caused, none architectural: 2 are the gate over-applying to basic ledger-integrity checks, 1 is a wrong dedup key, 1 is a missing `CREDIT_EXPOSURE_SV` column. 1 false positive is an instruction-wording gap. Full detail: `eval/results.md`.
- [x] Fixes redeployed and re-tested: **4/5 landed, 11/12 correct (v2, up from 7/12), zero regressions.** Remaining `correct_but_anomalous` false positive was a real calibration gap (book-wide vs. per-counterparty scale baseline), not a wording issue.
- [x] Fix #5 landed: **12/12 (v3)**, zero regressions across all three runs. `CREDIT_EXPOSURE_SV` gained a per-counterparty scale baseline (`counterparty_account_baseline_mean`/`_stddev`/`_count`) reusing the shared `ZSCORE` formula, and orchestration now cross-references `CONCENTRATION_GROUP` before calling a scale outlier a probable error. Landed differently than first written — Snowflake rejects a metric referencing another window-function metric, so the z-score is computed by the agent at query time rather than as a named metric; functionally identical. Full detail: `eval/results.md`.
- **Real bug caught in review, fixed before reaching Snowflake:** `sql/load_synthetic_data.sql` had no `TRUNCATE` before its `COPY INTO`s — re-running it against the regenerated (injected-case-carrying) CSVs would have duplicated every existing row, not just added the new ones. Fixed in the script itself.

## Days 17–18 — Rehearse & submit ⬜ NOT STARTED
- [ ] Dry-run the live path (Stage 0 + Stage 2) repeatedly
- [ ] Finalize pitch deck (penalty-disclosure impact framing)
- [ ] Submit
