# Build plan — task checklist

File-level TODOs for the remaining build, mapped to the folder scaffold below. Day-by-day narrative and rationale live in `architecture.md`'s Build plan section — this is the flat checklist to work off while coding. Check items off as they land.

**Status:** Days 1–3 done (jurisdiction, Snowflake account/Enterprise edition, lineage confirmed, real documents sourced). Starting Days 3–6.

---

## Folder layout

```
data/
  raw/            real sourced documents (circulars, Pillar 3, divergence, penalties) — populated
  synthetic/      generated GL/positions/counterparties/transactions — empty, generator writes here
sql/
  ddl/            table definitions (RULE_CORPUS, LINE_ITEM_MAP, GL_ENTRIES, POSITIONS,
                  COUNTERPARTIES, TRANSACTIONS, INJECTED_CASES, AUDIT_LOG, EVAL_RESULTS,
                  DIVERGENCE_DISCLOSURES)
  rbac/           role + grant scripts (ANALYST_READ, GOVERNANCE_WRITE, AUDIT_INSERT, OFFICER_SIGNOFF)
  semantic_views/ Cortex Analyst Semantic View definitions (transactions/positions/exposures)
generator/        synthetic data generation script(s)
skills/           SKILL.md files (signal-query, circular-interpret, assure-return, narrative-draft)
backend/          Agent SDK host service (Python/TS), one endpoint per stage
ui/               thin review UI
eval/             INJECTED_CASES catalogue + eval harness
brand/            logo assets — populated
```

---

## Days 3–6 — Synthetic data + Snowflake foundation

- [x] `generator/` — `generate_synthetic_data.py` (+ `anchors.py` with the real PDF figures, page-cited). **Done, exactly reconciled**: industry-wise fund/non-fund exposure (42 sectors), gross NPA, NPA provisions, and the 5-way NPA classification split all match HDFC's disclosed figures to the decimal (verified via a fragment-based exact-partition algorithm, not approximated). `EXPOSURE_CLASS` risk-weight buckets and `TRANSACTIONS` are documented approximations — no real per-industry disclosure exists to reconcile those against. Output: 605 counterparties, 2,064 positions, 2,206 GL entries, 24,540 transactions in `data/synthetic/`.
- [x] `sql/ddl/` — table DDL for `RULE_CORPUS`, `LINE_ITEM_MAP`, `GL_ENTRIES`, `POSITIONS`, `COUNTERPARTIES`, `TRANSACTIONS`, `INJECTED_CASES`, `AUDIT_LOG`, `EVAL_RESULTS`, `DIVERGENCE_DISCLOSURES` — written, **not yet run against Snowflake**. Two schemas: `PRAMAN.CORE` (runtime) and `PRAMAN.EVAL` (isolated, no Skill-role grant). Run order in `sql/ddl/README.md`.
- [x] Actually execute `sql/ddl/*.sql` against the account. **Done.** All 10 tables live: `PRAMAN.CORE` (`RULE_CORPUS`, `LINE_ITEM_MAP`, `COUNTERPARTIES`, `POSITIONS`, `GL_ENTRIES`, `TRANSACTIONS`, `DIVERGENCE_DISCLOSURES`, `AUDIT_LOG`) and `PRAMAN.EVAL` (`INJECTED_CASES`, `EVAL_RESULTS`) — verified via `SHOW TABLES IN DATABASE PRAMAN`, all currently 0 rows.
- [x] Load `data/synthetic/` output into the Snowflake tables above. **Done** — `sql/load_synthetic_data.sql` (PUT + COPY INTO), row counts verified independently in Snowflake: 605 / 2,064 / 2,206 / 24,540, and gross NPA sums to exactly ₹384,786.7M in-database, matching the source PDF.
- [ ] `sql/rbac/` — roles and grants: `ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT` (insert-only, no update/delete to any role), `OFFICER_SIGNOFF`
- [ ] Ingest `data/raw/circulars/RBI_DoS_2026-27_415_..._Supervisory_Returns_Directions_2026.txt` (or `...412...`) — chunk with page/section metadata, `CREATE CORTEX SEARCH SERVICE` over `RULE_CORPUS`
- [ ] Seed `LINE_ITEM_MAP` with approved mappings for the Pillar 3 line items in scope

## Days 6–9 — Semantic layer, detectors, Skills

- [ ] `sql/semantic_views/` — Cortex Analyst Semantic Views for transactions / positions / exposures (fork `semantic-view-patterns`)
- [ ] Deterministic detector logic (outlier scoring, structuring/velocity rules) — shared by Stage 0 and Stage 2
- [ ] `skills/signal-query.SKILL.md`
- [ ] `skills/circular-interpret.SKILL.md`
- [ ] `skills/assure-return.SKILL.md`
- [ ] `skills/narrative-draft.SKILL.md` (thin layer on the bundled governance lineage skill)

## Days 9–12 — Backend + review UI

- [ ] `backend/` — Agent SDK host, keypair auth, one endpoint per stage
- [ ] `ui/` — one screen per stage: ask/answer, findings list, gap analysis, lineage + narrative
- [ ] Wire every Skill call to write an `AUDIT_LOG` row

## Days 12–15 — Wire the four stages end-to-end

- [ ] Stage 0 live: NL question → answer
- [ ] Stage 2 live: draft return → ranked findings with citations
- [ ] Stage 1 slice: the sourced circular → gap analysis, change spec, test cases
- [ ] Stage 3 scripted walkthrough: one injected break → lineage trace → root cause + narrative

## Days 15–17 — Eval

- [ ] `eval/` — `INJECTED_CASES` catalogue (named error/signal types), isolated schema, no grant to Skills' runtime role
- [ ] Eval run against held-out cases (divergence disclosure, taxonomy delta, injected catalogue) — `EVAL_RESULTS`, `GROUP BY ERROR_TYPE`
- [ ] Evidence-pack export from `AUDIT_LOG`

## Days 17–18 — Rehearse & submit

- [ ] Dry-run the live path (Stage 0 + Stage 2) repeatedly
- [ ] Finalize pitch deck (penalty-disclosure impact framing)
- [ ] Submit
