# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Praman** — a citation-backed regulatory reporting and risk-signal copilot for banks/NBFCs, built on Snowflake's Coco CLI/Agent SDK. It's a solo hackathon build (Snowflake CoCo CLI Hackathon 2026, submission window 13–30 Sept 2026) targeting the India/RBI jurisdiction, anchored on HDFC Bank's real Basel III Pillar 3 disclosure.

Read these three docs in this order before making non-trivial changes — each supersedes assumptions in the last where they conflict:
1. `regulatory-reporting-problem-statement.md` — the hackathon brief and the four-stage product concept (Signal / Interpret / Assure / Explain).
2. `architecture.md` — the actual design, including corrections to the problem statement's platform assumptions (verified against live Snowflake behavior, not just docs). Contains the data model, RBAC design, eval architecture, and the day-by-day build plan.
3. `plan.md` — the flat, checkable file-level TODO list mirroring `architecture.md`'s build plan. This is the file to update as work lands (check off boxes, update the `**Status:**` line at the top).

`data-sources.md` tracks provenance/status of every real document the prototype depends on — check it before treating any figure in `data/raw/` as final; some sourcing gaps are logged there as open scope decisions, not silent gaps.

## Commands

Python package/deps are managed with `uv` (see `pyproject.toml`, `uv.lock`, `.python-version` = 3.12).

```bash
uv sync                                   # install/sync dependencies into .venv
uv run python generator/generate_synthetic_data.py   # regenerate data/synthetic/*.csv from anchors.py
uv run jupyter notebook notebooks/rbi_scraping.ipynb  # RBI scraping technique notebook
```

There is no test suite, linter, or build step configured yet. `main.py` is the uv scaffold stub, not part of the product.

SQL is run directly against Snowflake (via Coco CLI / Snowsight), not through a migration tool. `sql/ddl/README.md` documents the required run order (numbered files, FK-dependency order — Snowflake doesn't enforce FKs at write time but `CREATE TABLE ... REFERENCES` fails if the target table doesn't exist yet). Loading synthetic data into already-created tables is `sql/load_synthetic_data.sql` (PUT + COPY INTO).

## Architecture

### The core idea: one governed data model, four directions of traversal

Four product "stages" are really four different traversals over the same tables, not four separate features — this is what the whole design is organized around:
- **Stage 0 (Signal)** queries transaction/position data live via Cortex Analyst.
- **Stage 1 (Interpret)** walks a new circular's rule text forward onto the line-item map.
- **Stage 2 (Assure)** walks the same map backward from a draft return to rule text.
- **Stage 3 (Explain)** walks lineage down from a report line item to source GL/position rows.

The shared spine is `RULE_CORPUS` → `LINE_ITEM_MAP` → `GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS`, plus an append-only `AUDIT_LOG`. Full ER diagram and column-level table docs are in `architecture.md`'s "Shared data model" section — read that before adding or changing a table rather than inferring schema from the DDL alone, since the DDL doesn't explain *why* tables relate the way they do.

One detector implementation (outlier/structuring scoring, SQL/Python) feeds both Stage 0 and Stage 2 — never duplicate this logic per-stage.

### Two Snowflake schemas, deliberately isolated

`PRAMAN.CORE` (runtime tables Skills read/write) and `PRAMAN.EVAL` (`INJECTED_CASES`, `EVAL_RESULTS`). **`INJECTED_CASES` must never be reachable from a Skill's runtime role** — it's the eval answer key. This isolation is enforced via RBAC grants (`sql/rbac/`, not yet written as of this writing), not by convention, so any RBAC change must preserve "no grant to the Skills' runtime role on the `EVAL` schema."

### Skills are markdown, not code

A Coco "Skill" is a `SKILL.md` file (YAML frontmatter + workflow steps), not a compiled/RBAC-locked unit — see `architecture.md`'s platform capability notes. The planned skills (`skills/` is currently empty, scaffolded per `plan.md`): `signal-query` (Stage 0), `circular-interpret` (Stage 1, the only one with an extra `PARSE_DOCUMENT` pipeline step before Cortex Search indexing), `assure-return` (Stage 2), `narrative-draft` (Stage 3 — thin, since most of the real work is the bundled governance lineage skill, prompted rather than built). Before authoring a new skill, check it against `Snowflake-Labs/coco-skills` (the public bundled-skills repo) — `semantic-view-patterns` and the lineage/governance skill are confirmed reusable rather than needing custom builds.

### Synthetic data is bottom-up from real disclosed figures, not sampled

`generator/anchors.py` transcribes real numbers (with page references) from `data/raw/pillar3/HDFC_Bank_Basel_III_Pillar3_2026-06-30.pdf`. `generator/generate_synthetic_data.py` builds GL entries, positions, and a counterparty book that **exactly reconciles** (via a fragment-based exact-partition algorithm, not approximation) to those disclosed totals: industry-wise exposure, industry-wise gross NPA, NPA provisions, and the 5-way NPA classification split. `POSITIONS.EXPOSURE_CLASS` and `TRANSACTIONS` are documented approximations instead — no real per-industry disclosure exists to reconcile those against (see the docstring in `generate_synthetic_data.py` for exactly which invariants are exact vs. approximated). If you touch the generator, preserve this exact/approximate distinction and don't silently make an approximated field look reconciled.

### Backend/frontend split (not yet built)

Per `architecture.md`: the Coco Agent SDK is server-side only (Python/TS, holds the Snowflake connection via keypair auth) — it cannot be embedded in a browser. The planned `backend/` hosts the Agent SDK with one endpoint per stage; the planned `ui/` is a thin web client holding no data or Snowflake credentials of its own, talking only to the backend over an authenticated session. Both directories are currently empty scaffolds.

### Data residency / compute placement notes worth preserving

- Cortex Search does not ingest PDFs directly — the pipeline is `PARSE_DOCUMENT`/`AI_PARSE_DOCUMENT` (extract) → Cortex Search (chunk + index). Carry page/section metadata through chunking manually for paragraph-level citation.
- Native lineage (`GET_LINEAGE`) requires Enterprise Edition — confirmed working live on this project's account. Don't build custom lineage logic; prompt the bundled governance skill.
- Cross-region inference can route over the public internet with mTLS for cross-cloud cases (still inside Snowflake's perimeter, never third-party) — state this precisely rather than as an absolute "data never leaves the account" claim if it comes up in pitch material.
