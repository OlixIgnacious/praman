# Build tracker — Praman

Quick status view across the full build, all phases in one place. Update the checkbox and the phase status line as work lands; `plan.md` still holds the folder layout and file-level detail, `architecture.md` holds the day-by-day rationale — this file is just "what's done vs. not," nothing more.

**Overall:** 4 of 8 phases done, 1 in progress. Currently in **Days 3–6** — one item left (seed `LINE_ITEM_MAP`).

---

## Day 1 — Decide & de-risk ✅ DONE
- [x] Pick jurisdiction (India/RBI) — Basel III Pillar 3 substitutes for gated CIMS returns; divergence disclosures substitute for amended-vs-original filing pairs
- [x] Provision Snowflake account + Coco CLI access, confirm region/residency (`SBOBPMM-YB05177`, `AWS_AP_SOUTHEAST_7`, upgraded to Enterprise Edition)
- [x] Spike: confirm native lineage tracing works (`cortex lineage` tested live on Enterprise)

## Days 2–3 — Real data sourcing ✅ DONE
- [x] Pull real documents for India: circulars (2), Pillar 3 disclosure (HDFC), divergence disclosures (3), penalty disclosures (2), AML/sanctions circulars (2) — tracked in `data-sources.md`
- [x] Pick the Pillar 3 disclosure anchoring the synthetic firm — HDFC Bank, quarter ending 2026-06-30

## Days 3–6 — Synthetic data + Snowflake foundation 🔶 IN PROGRESS
- [x] `generator/generate_synthetic_data.py` + `anchors.py` — 605 counterparties, 2,064 positions, 2,206 GL entries, 24,540 transactions, exactly reconciled to HDFC's disclosed figures
- [x] `sql/ddl/` — all 10 table DDLs written
- [x] Execute `sql/ddl/*.sql` against Snowflake — all 10 tables live in `PRAMAN.CORE` / `PRAMAN.EVAL`
- [x] Load `data/synthetic/` into Snowflake — row counts verified, gross NPA matches PDF exactly
- [x] `sql/rbac/` — roles + grants written and applied to Snowflake (`ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT` insert-only, `OFFICER_SIGNOFF`) — verified: no role has `UPDATE`/`DELETE` on `AUDIT_LOG`
- [x] Ingest circular 415 into `RULE_CORPUS` — 30 chunks loaded, `RULE_CORPUS_SEARCH` Cortex Search Service created and granted to `ANALYST_READ`
- [ ] Seed `LINE_ITEM_MAP` with approved mappings for the Pillar 3 line items in scope

## Days 6–9 — Semantic layer, detectors, Skills ⬜ NOT STARTED
- [ ] `sql/semantic_views/` — Cortex Analyst Semantic Views (transactions/positions/exposures), forked from `semantic-view-patterns`
- [ ] Deterministic detector logic (outlier scoring, structuring/velocity rules) — shared by Stage 0 and Stage 2
- [ ] `skills/signal-query.SKILL.md`
- [ ] `skills/circular-interpret.SKILL.md`
- [ ] `skills/assure-return.SKILL.md`
- [ ] `skills/narrative-draft.SKILL.md` (thin layer on bundled governance lineage skill)

## Days 9–12 — Backend + review UI ⬜ NOT STARTED
- [ ] `backend/` — Agent SDK host, keypair auth, one endpoint per stage
- [ ] `ui/` — one screen per stage: ask/answer, findings list, gap analysis, lineage + narrative
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
