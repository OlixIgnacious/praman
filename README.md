# Praman

Citation-backed regulatory reporting and risk-signal copilot for banks and NBFCs, built on Snowflake's Coco CLI / Cortex stack.

Solo build for the **Snowflake CoCo CLI Hackathon 2026** (Hack2skill, GCC Edition), track *Risk, Fraud and Regulatory Intelligence Copilot (Banking / NBFC)*. Submission window 13–30 Sept 2026, Final Demo Days 27–30 Oct 2026. Jurisdiction: India (RBI), anchored on HDFC Bank's real Basel III Pillar 3 disclosure.

## The problem

Regulatory reporting is high-volume and still largely manual: a circular arrives, analysts argue about what it means and hunt through a mapping spreadsheet for which report fields move; a draft return gets eyeballed against rule text before an officer signs it; when something's wrong, someone spends days tracing a number back through source systems to explain it. Deterministic rule engines already handle the arithmetic (cross-footing, validity edits, outlier scoring). What's missing is the genuinely-reasoning part: interpreting a circular, explaining *why* a number looks the way it does, and writing an explanation a regulator will accept.

Full problem statement: [`regulatory-reporting-problem-statement.md`](regulatory-reporting-problem-statement.md).

## What it does — four stages, one data model

| Stage | Trigger | Does | Snowflake service |
|---|---|---|---|
| **0 — Signal** | NL question | Surfaces risk/fraud/liquidity signals from live data; AML-adjacent flags route to a compliance queue, never auto-resolved | Cortex Analyst (Semantic Views) |
| **1 — Interpret** | New circular/taxonomy | Maps changed requirements onto report line items; gap analysis, change spec, test cases — human-approved before anything commits | Cortex Search over the rule corpus |
| **2 — Assure** | Draft return, pre-filing | Validates against rule text, filing history, and peer benchmarks; ranked findings, each with a citation | Cortex Search + Cortex Analyst |
| **3 — Explain** | Confirmed break/signal | Traces lineage to ranked root causes, proposes remediation, drafts a narrative — draft only, human sign-off before use | Native Snowflake lineage |

These four stages are four different traversals over one governed data model, not four separate features — see [`architecture.md`](architecture.md)'s "Per-stage component architecture" for the full diagram. The shared spine: `RULE_CORPUS` → `LINE_ITEM_MAP` → `GL_ENTRIES` / `POSITIONS` / `COUNTERPARTIES` / `TRANSACTIONS`, plus an append-only `AUDIT_LOG`.

## Architecture highlights

- **One detector, two consumers.** A single `ZSCORE` UDF backs both the Stage 0 structuring/velocity signal and the Stage 2 draft-return outlier check — never two independently-tuned copies of the same anomaly logic. (`sql/detectors/`)
- **Append-only by grant, not convention.** No Snowflake role is ever granted `UPDATE`/`DELETE` on `AUDIT_LOG`; a maker-checker sign-off is recorded as a new row, never an edit of the original. (`sql/rbac/`)
- **`INJECTED_CASES` (the eval answer key) is schema-isolated** from every role a Skill runs as, so a bug can't let the agent see what it's being scored against.
- **Every rule citation points at RBI's own numbered paragraph**, not an arbitrary chunk boundary — see [`ingest/README.md`](ingest/README.md) for the chunking approach.
- **Synthetic data is exactly reconciled, not sampled.** The generator builds a GL/position/counterparty book from scratch that sums, to the decimal, to HDFC Bank's real disclosed Pillar 3 figures — enforced by the test suite, not just eyeballed.
- **Platform assumptions are checked against live Snowflake behavior, not just docs**, and corrected in `architecture.md` when they don't hold (e.g. Cortex Search's PDF-parsing requirement, native lineage's edition requirement, and the original custom-backend-plus-UI plan, superseded by a native Cortex Agent + CoWork once a live spike confirmed it).
- **No custom backend at all.** `PRAMAN.CORE.SIGNAL_ASSURE_AGENT` is a native `CREATE AGENT` object (Stage 0 + Stage 2, six tools) connected to Snowflake's own chat surface, CoWork (`ai.snowflake.com`) — there's no externally-hosted service and no standing credential to secure. `backend/`/`ui/` stay empty scaffolds.

Full design, RBAC model, eval architecture, and day-by-day build plan: [`architecture.md`](architecture.md).

## Status

All build phases are done through Days 1–17 (data, RBAC, Semantic Views, the `SIGNAL_ASSURE_AGENT` Cortex Agent, all four stages wired end-to-end, eval at 12/12 with zero regressions) — see `architecture.md`'s Build plan for the full day-by-day detail. Only rehearsal, pitch, and submission remain. (Day-to-day status tracking and pending-manual-run notes are kept locally in gitignored `TRACKER.md`/`NOTES.md`, not part of this repo.)

## Getting started

Python deps are managed with [`uv`](https://docs.astral.sh/uv/).

```bash
uv sync                                               # install dependencies
uv run pytest tests/                                  # run the test suite (fully local, no Snowflake needed)
uv run python generator/generate_synthetic_data.py    # regenerate data/synthetic/*.csv from anchors.py
uv run python ingest/chunk_circular.py <path>          # chunk a scraped circular into RULE_CORPUS rows
```

SQL (table DDL, RBAC, Semantic Views, detectors, seeds) lives under `sql/` and runs directly against Snowflake via the `cortex` CLI or Snowsight — each `sql/` subdirectory has its own `README.md` with run order and design rationale.

## Repository layout

| Path | Contents |
|---|---|
| `sql/ddl/` | Table DDL — `RULE_CORPUS`, `LINE_ITEM_MAP`, `GL_ENTRIES`, `POSITIONS`, `COUNTERPARTIES`, `TRANSACTIONS`, `DIVERGENCE_DISCLOSURES`, `AUDIT_LOG`, plus the isolated `EVAL` schema |
| `sql/rbac/` | The four functional roles (`ANALYST_READ`, `GOVERNANCE_WRITE`, `AUDIT_INSERT`, `OFFICER_SIGNOFF`) and their grants |
| `sql/semantic_views/` | Cortex Analyst Semantic Views — transactions, positions, credit exposure |
| `sql/detectors/` | The shared outlier/structuring detector (one UDF, two consuming views) |
| `generator/` | Synthetic GL/position/counterparty/transaction data generator, bottom-up from real disclosed figures |
| `ingest/` | Circular → citable `RULE_CORPUS` row chunking pipeline |
| `skills/` | Four real, loadable Coco skills, one per stage — each its own directory (`skills/<name>/SKILL.md`), verified locally with `cortex skill add`. Installable by anyone directly from this GitHub repo. |
| `cortex_project/` | `SIGNAL_ASSURE_AGENT.agent.yaml` — the live Cortex Agent spec (Stage 0 + Stage 2, six tools) |
| `data/raw/` | Real sourced documents — circulars, Pillar 3 disclosure, divergence disclosures, penalty disclosures |
| `data/synthetic/` | Generator output |
| `data/processed/` | Ingest pipeline output (chunked rule corpus, ready to load) |
| `eval/` | Eval harness and injected-case catalogue — `run_eval.md` (12-case runbook), `results.md` (12/12, zero regressions across three runs) |
| `demos/` | Worked Stage 1 gap-analysis and Stage 3 lineage walkthroughs, run against real project data |
| `backend/`, `ui/` | Empty scaffolds — superseded by the native Cortex Agent + CoWork, see above |
| `tests/` | Local pytest suite — generator reconciliation + chunker correctness |
| `notebooks/` | RBI scraping technique notebook |

## Data sources

Every real document this prototype depends on, with sourcing status, is tracked in [`data-sources.md`](data-sources.md) — some gaps there are logged as open scope decisions, not silent gaps.

## Docs index

| File | Purpose |
|---|---|
| `regulatory-reporting-problem-statement.md` | The hackathon brief |
| `architecture.md` | Full design, platform-capability notes, data model, RBAC, eval architecture, day-by-day build plan (the source of truth for build status) |
| `jurisdiction_agnostic_analysis.md` | Code-level audit of what's genuinely jurisdiction-agnostic vs. India/RBI-coupled, plus the checklist for validating a second jurisdiction |
| `production_deployment_analysis.md` | Code-level audit of what it would actually take to deploy against a real institution's own schema — separate question from jurisdiction-agnosticism |
| `plug_and_play_architecture.md` | Design for a genuinely reusable deployment: canonical schema contract, per-jurisdiction/per-institution adaptor boundaries, the domain-coverage limit (credit risk vs. e.g. securities trading), and the data-pipeline layer this project doesn't have yet |
| `data-sources.md` | Provenance/status of every real sourced document |

`plan.md`/`TRACKER.md`/`NOTES.md`/`CLAUDE.md` (day-by-day TODOs, quick status, pending manual Snowflake runs, dev-tooling guidance) are gitignored local working files for the build process — not shipped in this repo.
