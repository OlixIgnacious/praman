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
- [x] `sql/rbac/` — roles and grants: `ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT` (insert-only, no update/delete to any role), `OFFICER_SIGNOFF`. **Written and applied to Snowflake.** `OFFICER_SIGNOFF` records sign-off as a new `AUDIT_LOG` insert (never an `UPDATE`), keeping the table append-only end to end. No grants on `PRAMAN.EVAL` (deliberate). Run order/design in `sql/rbac/README.md`.
- [x] Ingest `data/raw/circulars/RBI_DoS_2026-27_415_..._Supervisory_Returns_Directions_2026.txt` — chunk with page/section metadata, `CREATE CORTEX SEARCH SERVICE` over `RULE_CORPUS`. **Done.** `ingest/chunk_circular.py` splits the scraped-text circular into RULE_CORPUS rows at RBI's own paragraph numbering (the citable unit — e.g. "para 21"), nested under chapter/subsection via `SECTION_REF`; no PAGE_NO since this source is scraped HTML, not a parsed PDF (see `ingest/README.md` for the full chunking writeup). 30 chunks loaded into `PRAMAN.CORE.RULE_CORPUS` via `sql/load_rule_corpus.sql`; `RULE_CORPUS_SEARCH` Cortex Search Service created over `CHUNK_TEXT` via `sql/create_rule_corpus_search.sql` (warehouse `COMPUTE_WH`), with `ANALYST_READ` granted `USAGE` on it.
- [x] Seed `LINE_ITEM_MAP` for the Pillar 3 line items in scope. **Written and run.** `sql/seed_line_item_map.sql` — 9 rows (industry fund/non-fund exposure, industry gross NPA, industry provisions, 5-way NPA classification split), matching exactly what `generate_synthetic_data.py`'s docstring calls "exactly reconciled." All cite `RULE_CHUNK_ID = 'RBI/DoS/2026-27/415#21'` (RAQ return description — the closest ingested rule text, not the actual Pillar 3 disclosure norms circular, which isn't in `RULE_CORPUS` yet — flagged honestly in the script). `STATUS='proposed'` on every row by design (maker-checker: a seeding script isn't the human governance approval step) — a follow-up `GOVERNANCE_WRITE` approval pass is still needed before Stage 2/3 should treat these as committed.

## Days 6–9 — Semantic layer, detectors, Skills

- [x] `sql/semantic_views/` — Cortex Analyst Semantic Views for transactions / positions / exposures (forked `semantic-view-patterns`). **Written and deployed.** `TRANSACTIONS_SV` (event-level, fully additive, rolling 7-day structuring-signal building blocks), `POSITIONS_SV` (semi-additive `NOTIONAL`, concentration-% metric), `CREDIT_EXPOSURE_SV` (mirrors the Pillar 3 line items in `LINE_ITEM_MAP` — fund/nonfund exposure, gross NPA, provisions, NPA ratio, coverage ratio). Each grants `ANALYST_READ` `SELECT` on itself (corrected from `GRANT USAGE`, which isn't a valid privilege on a Semantic View, during deployment). `LIKE ... ESCAPE` in `CREDIT_EXPOSURE_SV`'s dimensions also had to become `STARTSWITH(...)` to deploy. Design rationale and pattern sourcing in `sql/semantic_views/README.md`.
- [x] Deterministic detector logic (outlier scoring, structuring/velocity rules) — shared by Stage 0 and Stage 2. **Written and deployed.** `sql/detectors/`: `ZSCORE` UDF is the one shared formula; `TRANSACTION_SIGNALS` (Stage 0, per-counterparty daily structuring/velocity z-scores vs. trailing 90-day baseline) and `GL_OUTLIER_SIGNALS` (Stage 2, per-`ACCOUNT_CODE` monthly amount z-scores vs. trailing 6-month baseline, feeding draft-return-vs-filing-history checks) both call it. No near-threshold-clustering heuristic yet (would need a real CTR/reporting-threshold circular ingested first — flagged in `sql/detectors/README.md`, not hidden).
- [x] `skills/signal-query.SKILL.md` — Stage 0: queries `TRANSACTIONS_SV`/`POSITIONS_SV`/`CREDIT_EXPOSURE_SV`/`TRANSACTION_SIGNALS`; AML-adjacent flags route to compliance queue, never auto-resolve
- [x] `skills/circular-interpret.SKILL.md` — Stage 1: ingestion-check → retrieve via `RULE_CORPUS_SEARCH` → cross-reference `LINE_ITEM_MAP` → propose (`STATUS='proposed'` only, never self-approves)
- [x] `skills/assure-return.SKILL.md` — Stage 2: validates only `STATUS='approved'` `LINE_ITEM_MAP` rows (flags explicitly that our current seed is all `proposed`); reuses `GL_OUTLIER_SIGNALS`, the same detector as Stage 0
- [x] `skills/narrative-draft.SKILL.md` — Stage 3: thin layer over native `cortex lineage`, confirmed working (Day 1 spike) — deliberately does not reimplement lineage tracing

## Days 9–12 — Backend + review UI

- [x] **Spike:** create one real Cortex Agent over `TRANSACTIONS_SV`, connect to CoWork, ask it a live question end-to-end. **Done — holds up.** `PRAMAN.CORE.TRANSACTIONS_AGENT` (spec: `cortex_project/TRANSACTIONS_AGENT.agent.yaml`) live at `ai.snowflake.com`, correct answer to "What is the total transaction amount by channel?" with a generated chart. Quirk noted: generated SQL sometimes falls back to inline `SUM(amount)` instead of referencing the `total_amount` metric by name — worth watching once guarded metrics (semi-additive, trailing-window) are in play.
- [ ] Proceeding on Cortex Agent + CoWork: extend to `POSITIONS_SV`, `CREDIT_EXPOSURE_SV` (as additional `cortex_analyst_text_to_sql` tools) and `RULE_CORPUS_SEARCH` (as a `cortex_search` tool); distill each `SKILL.md`'s workflow into the agent's `instructions.orchestration`/`instructions.response`
- [ ] Open design call before extending further: one agent with multiple tools, or one agent per stage — see `architecture.md`'s Days 9–12 item 18
- [ ] Scope remaining custom backend to what CoWork can't do declaratively: `AUDIT_LOG` writes per invocation (no native hook confirmed yet), Stage 1/3's bespoke orchestration (circular ingestion, lineage-to-narrative)
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
