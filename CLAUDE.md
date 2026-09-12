# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Praman** — a citation-backed regulatory reporting and risk-signal copilot for banks/NBFCs, built on Snowflake's Coco CLI. It's a solo hackathon build (Snowflake CoCo CLI Hackathon 2026, submission window 13–30 Sept 2026) targeting the India/RBI jurisdiction, anchored on HDFC Bank's real Basel III Pillar 3 disclosure.

Read in this order before making non-trivial changes — each supersedes assumptions in the last where they conflict:
1. `regulatory-reporting-problem-statement.md` — the hackathon brief and the four-stage product concept (Signal / Interpret / Assure / Explain).
2. `architecture.md` — the actual design, including corrections to the problem statement's platform assumptions, verified against live Snowflake behavior as they're found (not just docs) — e.g. Cortex Search's PDF-parsing requirement, native lineage's edition requirement, and a native Cortex Agent/CoWork capability that may replace most of the originally-planned custom backend+UI. Contains the data model, RBAC design, eval architecture, and the day-by-day build plan.
3. `TRACKER.md` — the current "what's done vs. not" status at a glance, one line per build-plan item, kept in sync as work lands. Check this first for current state rather than assuming from file presence alone (e.g. a `sql/*.sql` file existing doesn't mean it's been run against Snowflake yet — many scripts in this repo are written but not yet executed; `TRACKER.md` and `NOTES.md` track that distinction).
4. `NOTES.md` — pending manual Snowflake runs, when present. Non-interactive `cortex exec` auto-denies mutating SQL (`CREATE`/`GRANT`/`INSERT`/etc.), so DDL/DML/grant scripts in this repo are written here but executed by a human in an interactive `cortex` session, not by an agent running headless. Check this file for exact run commands before assuming a written SQL script has taken effect.
5. `plan.md` — the flat, checkable file-level TODO list mirroring `architecture.md`'s build plan, with per-item implementation notes. Update as work lands (check off boxes, update the `**Status:**` line at the top).

`data-sources.md` tracks provenance/status of every real document the prototype depends on — check it before treating any figure in `data/raw/` as final; some sourcing gaps are logged there as open scope decisions, not silent gaps.

## Commands

Python package/deps are managed with `uv` (see `pyproject.toml`, `uv.lock`, `.python-version` = 3.12).

```bash
uv sync                                               # install/sync dependencies into .venv
uv run python generator/generate_synthetic_data.py    # regenerate data/synthetic/*.csv from anchors.py
uv run python ingest/chunk_circular.py <path> [--out ...] [--append]  # chunk a scraped circular into RULE_CORPUS rows
uv run jupyter notebook notebooks/rbi_scraping.ipynb   # RBI scraping technique notebook
uv run pytest tests/                                   # run the test suite (generator + chunker, all local — no Snowflake needed)
uv run pytest tests/test_generator.py -v -k <name>     # single file / single test
```

There is no linter or build step configured. `main.py` is the uv scaffold stub, not part of the product.

**SQL runs directly against Snowflake** (via the `cortex` CLI or Snowsight), not through a migration tool, and **not from this agent non-interactively** — see `NOTES.md` above. Run order within each `sql/` subdirectory is documented in that subdirectory's own `README.md`:
- `sql/ddl/` — table DDL (numbered, FK-dependency order)
- `sql/rbac/` — the four functional roles and their grants
- `sql/semantic_views/` — the four Cortex Analyst Semantic Views (transactions, positions, credit exposure, and `LINE_ITEM_MAP` itself — the last one exists specifically so a Cortex Agent can query governance `STATUS` before computing a value, see below)
- `sql/detectors/` — the shared outlier/structuring detector (one UDF, two consuming views)
- `sql/load_synthetic_data.sql`, `sql/load_rule_corpus.sql`, `sql/create_rule_corpus_search.sql`, `sql/seed_line_item_map.sql` — one-off loads/seeds at the repo root of `sql/`, run after their respective DDL exists

## Architecture

### The core idea: one governed data model, four directions of traversal

Four product "stages" are really four different traversals over the same tables, not four separate features — this is what the whole design is organized around:
- **Stage 0 (Signal)** queries transaction/position/exposure data live via Cortex Analyst Semantic Views.
- **Stage 1 (Interpret)** walks a new circular's rule text forward onto the line-item map.
- **Stage 2 (Assure)** walks the same map backward from a draft return to rule text.
- **Stage 3 (Explain)** walks lineage down from a report line item to source GL/position rows.

The shared spine is `RULE_CORPUS` → `LINE_ITEM_MAP` → `GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS`, plus an append-only `AUDIT_LOG`. Full ER diagram and column-level table docs are in `architecture.md`'s "Shared data model" section — read that before adding or changing a table rather than inferring schema from the DDL alone, since the DDL doesn't explain *why* tables relate the way they do.

**One detector, two consumers, literally.** `sql/detectors/01_zscore_udf.sql` defines a single `ZSCORE` UDF; `TRANSACTION_SIGNALS` (Stage 0, per-counterparty daily structuring/velocity) and `GL_OUTLIER_SIGNALS` (Stage 2, per-`ACCOUNT_CODE` monthly outliers vs. filing history) both call it. Never re-derive z-score anomaly logic inline in a skill — query these views.

### Two Snowflake schemas, deliberately isolated

`PRAMAN.CORE` (runtime tables Skills read/write) and `PRAMAN.EVAL` (`INJECTED_CASES`, `EVAL_RESULTS`). **`INJECTED_CASES` must never be reachable from a Skill's runtime role** — it's the eval answer key. This isolation is enforced via RBAC grants (`sql/rbac/`) — none of the four roles (`ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT`, `OFFICER_SIGNOFF`) is ever granted anything on `PRAMAN.EVAL`. Any RBAC change must preserve that.

`AUDIT_LOG` is append-only **by grant, not convention**: no role, anywhere, is ever granted `UPDATE`/`DELETE` on it. A maker-checker sign-off is recorded as a *new* `AUDIT_LOG` row (`OFFICER_SIGNOFF` role), never an `UPDATE` of the original run's row — preserve this if you touch sign-off logic.

### LINE_ITEM_MAP: proposed vs. approved is a real, currently-relevant gate

Every `LINE_ITEM_MAP` row starts `STATUS = 'proposed'` until a `GOVERNANCE_WRITE` session explicitly approves it — a seeding/proposing script never self-approves (see `sql/seed_line_item_map.sql`'s header comment). **As of this writing, 1 of the 9 seeded rows (`PILLAR3.IND_NPA.GROSS`) is `approved`; the other 8 are still `proposed`.** `assure-return` (Stage 2) is written to check `STATUS` per line item and explicitly refuse to validate against an unapproved mapping — don't build anything that silently falls back to a proposed row as if it were governance-reviewed.

**A real bug already happened here, worth knowing before touching Stage 2 again:** the first version of `SIGNAL_ASSURE_AGENT` had no tool to actually query `LINE_ITEM_MAP` at all — its "no approved mapping" answers were a hardcoded default, not a real check, and this passed testing by accident (every row happened to be `proposed`, so the default and the correct answer coincided). Fixed by adding `LINE_ITEM_MAP_SV` (a Semantic View over `LINE_ITEM_MAP` itself, `sql/semantic_views/04_line_item_map_sv.sql`) and a `line_item_map_lookup` tool, made the mandatory first step of every Stage 2 flow. If you add a new gate/check to a Skill or agent, verify it against a case where the check would fail, not just one where the default answer happens to be right.

### Skills are markdown, not code

A Coco "Skill" is a `SKILL.md` file (YAML frontmatter + workflow steps), not a compiled/RBAC-locked unit. All four are written, in `skills/`: `signal-query` (Stage 0), `circular-interpret` (Stage 1 — the one with an extra ingestion-pipeline step, see below), `assure-return` (Stage 2 — the `STATUS='approved'` gate above lives here), `narrative-draft` (Stage 3 — deliberately thin, delegating to the native `cortex lineage` capability rather than reimplementing lineage tracing). Before authoring a new Semantic View or Skill pattern, check `Snowflake-Labs/coco-skills` (`cortex skill add Snowflake-Labs/coco-skills`) — `semantic-view-patterns` (25 forkable join/metric/dimension patterns, used for all four Semantic Views here) and the bundled `lineage` capability are confirmed reusable rather than needing custom builds.

### Circular ingestion: scraped text → citable RULE_CORPUS rows

`ingest/chunk_circular.py` turns a scraped RBI Master Direction (`data/raw/circulars/*.txt` — plain text, not a PDF, so no `PARSE_DOCUMENT` step and no page numbers) into `RULE_CORPUS` rows chunked at RBI's own numbered-paragraph grain (the actual citable unit — "para 21", not an arbitrary token window). Full algorithm writeup, worked examples, and known limits in `ingest/README.md`. `sql/load_rule_corpus.sql` loads the resulting CSV (`data/processed/rule_corpus_chunks.csv`); `sql/create_rule_corpus_search.sql` builds the Cortex Search Service over it. A genuinely new PDF circular (as opposed to an already-scraped text one) still needs `PARSE_DOCUMENT`/`AI_PARSE_DOCUMENT` upstream of this pipeline — not yet built, since every circular sourced so far was scraped as text.

### Synthetic data is bottom-up from real disclosed figures, not sampled

`generator/anchors.py` transcribes real numbers (with page references) from `data/raw/pillar3/HDFC_Bank_Basel_III_Pillar3_2026-06-30.pdf`. `generator/generate_synthetic_data.py` builds GL entries, positions, and a counterparty book that **exactly reconciles** (via a fragment-based exact-partition algorithm, not approximation) to those disclosed totals: industry-wise exposure, industry-wise gross NPA, NPA provisions, and the 5-way NPA classification split — enforced by `tests/test_generator.py`'s reconciliation tests, not just the script's own `verify()` printout. `POSITIONS.EXPOSURE_CLASS` and `TRANSACTIONS` are documented approximations instead — no real per-industry disclosure exists to reconcile those against. If you touch the generator, preserve this exact/approximate distinction and don't silently make an approximated field look reconciled. `GL_ENTRIES.ACCOUNT_CODE` conventions worth knowing before writing SQL against it: `ADVANCES_FUND`/`ADVANCES_NONFUND` (performing), `NPA_<classification>` (non-performing, e.g. `NPA_DOUBTFUL_1`), `NPA_PROVISION` (contra-account, stored as a **negative** amount). NPA classification only ever applies to the fund-based book.

### Review UI is a native Cortex Agent + CoWork, not a custom build

`architecture.md` originally assumed a custom Python/TS backend (hosting a Coco Agent SDK) plus a custom thin web frontend — that plan was superseded after a live spike confirmed a better platform fit. **`PRAMAN.CORE.SIGNAL_ASSURE_AGENT`** (spec: `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml`, deployed via the bundled `agent-studio` skill) is a native Snowflake `CREATE AGENT` object covering Stage 0 + Stage 2 together (one agent, not one per stage — see `.claude/plans/lets-decide-what-would-rippling-lighthouse.md` for why), with six tools: `transaction_analytics`/`position_analytics`/`credit_exposure_analytics` (the three data Semantic Views), `line_item_map_lookup` (the Stage 2 governance gate — see above), `rule_corpus_search`, and `write_audit_log` (a `generic` tool wrapping `SP_WRITE_AUDIT_LOG`, `sql/procedures/`). It's live at CoWork (`ai.snowflake.com`, display name "Praman Signal + Assure") — `backend/`/`ui/` stay empty scaffolds; the only backend work still ahead of Stage 1 (`circular-interpret`) and Stage 3 (`narrative-draft`) is their bespoke multi-step orchestration, which doesn't fit a chat-agent's tool-call model. `demos/` has worked Stage 1/Stage 3 walkthroughs run against real project data.

A `generic` tool's `input_schema` doesn't support `array`-typed properties in practice, and a Cortex Agent silently drops arguments it treats as optional (breaking positional stored-procedure calls) — both real limitations found deploying this agent, documented in `sql/procedures/README.md` and `plan.md`'s Days 9–12 entry. Also: `cortex lineage` can only start tracing from a table/view, not a Semantic View — trace from the base table and read its downstream instead (`demos/stage3_lineage_walkthrough.md`).

### Data residency / compute placement notes worth preserving

- Cortex Search does not ingest PDFs directly — the pipeline is `PARSE_DOCUMENT`/`AI_PARSE_DOCUMENT` (extract) → Cortex Search (chunk + index). Carry page/section metadata through chunking manually for paragraph-level citation (see `ingest/chunk_circular.py` for the non-PDF case).
- Native lineage (`GET_LINEAGE`/`cortex lineage`) requires Enterprise Edition — confirmed working live on this project's account. Don't build custom lineage logic; prompt the bundled governance skill (`narrative-draft.SKILL.md`).
- Cross-region inference can route over the public internet with mTLS for cross-cloud cases (still inside Snowflake's perimeter, never third-party) — state this precisely rather than as an absolute "data never leaves the account" claim if it comes up in pitch material.
