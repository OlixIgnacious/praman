# Build tracker — Praman

Quick status view across the full build, all phases in one place. Update the checkbox and the phase status line as work lands; `plan.md` still holds the folder layout and file-level detail, `architecture.md` holds the day-by-day rationale — this file is just "what's done vs. not," nothing more.

**Overall:** 6 of 8 phases done, 1 in progress. Currently in **Days 9–12** — spike confirmed, building out the agent(s).

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

## Days 9–12 — Backend + review UI 🔶 IN PROGRESS — spike confirmed, building out
- [x] **Spike confirmed:** `PRAMAN.CORE.TRANSACTIONS_AGENT` live, CoWork-connected, correct live answers — Cortex Agent + CoWork replaces most of the originally-planned custom backend/UI
- [x] **Decided:** one combined agent for Stage 0 + Stage 2 (not one per stage) — rationale in `.claude/plans/lets-decide-what-would-rippling-lighthouse.md`
- [~] `SIGNAL_ASSURE_AGENT` (5 tools, supersedes `TRANSACTIONS_AGENT`) + `SP_WRITE_AUDIT_LOG` written; **not yet deployed** — run commands + verification checklist in `NOTES.md`
- [ ] Remaining custom backend scoped to Stage 1/3 orchestration only (audit logging now handled via the agent's own procedure tool, pending verification it's reliably called)
- [ ] Wire every Skill call to write an `AUDIT_LOG` row

## Days 12–15 — Wire the four stages end-to-end ⬜ NOT STARTED
- [ ] Stage 0 live: NL question → answer
- [ ] Stage 2 live: draft return → ranked findings with citations
- [ ] Stage 1 slice: sourced circular → gap analysis, change spec, test cases
- [ ] Stage 3 scripted walkthrough: one injected break → lineage trace → root cause + narrative

## Days 15–17 — Eval ⬜ NOT STARTED
- [ ] `eval/` — `INJECTED_CASES` catalogue, isolated schema, no grant to Skills' runtime role
- [ ] Eval run against held-out cases → `EVAL_RESULTS`, precision/recall `GROUP BY ERROR_TYPE`
- [ ] Evidence-pack export from `AUDIT_LOG`

## Days 17–18 — Rehearse & submit ⬜ NOT STARTED
- [ ] Dry-run the live path (Stage 0 + Stage 2) repeatedly
- [ ] Finalize pitch deck (penalty-disclosure impact framing)
- [ ] Submit
