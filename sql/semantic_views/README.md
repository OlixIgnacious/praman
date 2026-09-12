# Semantic Views — run order and design

Three Cortex Analyst Semantic Views, one per bounded domain (`architecture.md`: "build one Semantic View per bounded domain... rather than one giant model"). Run after `sql/ddl/` and the synthetic data load — each `CREATE OR REPLACE SEMANTIC VIEW` reads live table shapes, and each ends with a `GRANT SELECT ... TO ROLE ANALYST_READ` (which must already exist — see `sql/rbac/`). `SELECT`, not `USAGE` — `USAGE` isn't a valid privilege on a Semantic View, found while actually deploying these.

1. `01_transactions_sv.sql` — `TRANSACTIONS_SV`
2. `02_positions_sv.sql` — `POSITIONS_SV`
3. `03_credit_exposure_sv.sql` — `CREDIT_EXPOSURE_SV`

Independent of each other — any order works, listed in dependency-free numeric order for consistency with `sql/ddl/`.

## Forked from `semantic-view-patterns`

Per `architecture.md`'s Build plan ("Fork as starting template, don't author from scratch"), these were built against the bundled `Snowflake-Labs/coco-skills` skill (`cortex skill add Snowflake-Labs/coco-skills`), in **Apply mode**: read the pattern's DDL + README, mapped its structural roles onto our actual `PRAMAN.CORE` columns, generated DDL directly (this project has no YAML anywhere else, so DDL over `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` for consistency).

| View | Patterns forked | Why |
|---|---|---|
| `TRANSACTIONS_SV` | `entity_facts` (counterparty as shared dimension), `window_metrics` (trailing-window aggregates) | Transactions are event-level facts — fully additive. Rolling 7-day count/volume are raw structuring-signal building blocks (the actual detector logic is separate — see `plan.md`'s "deterministic detector" item). |
| `POSITIONS_SV` | `semi_additive_metric` (point-in-time balances), a whole-table `OVER()` ratio for concentration | `NOTIONAL` is a snapshot, not a transaction — additive across counterparties on one `AS_OF_DATE`, not across dates. `pct_of_total_notional` directly supports the Stage 0 "concentration limits" example query. |
| `CREDIT_EXPOSURE_SV` | `derived_metrics` (ratio metrics referencing other metrics by name), `entity_facts` (CASE-derived categorical dimensions) | Mirrors the Pillar 3 line items seeded into `LINE_ITEM_MAP` (`sql/seed_line_item_map.sql`) — same aggregation logic, expressed as live Cortex Analyst metrics instead of `TRANSFORM_LOGIC` text. Keep both in sync if either changes. |

## Things that would silently produce wrong numbers if missed

- **`POSITIONS_SV.total_notional` is `NON ADDITIVE BY (as_of_date)`.** The synthetic book currently has exactly one `AS_OF_DATE`, so this costs nothing today — but the moment a second snapshot date is loaded, summing `total_notional` without grouping by date would silently double-count. The guard is there before it's needed, not after.
- **`CREDIT_EXPOSURE_SV.npa_ratio` divides by `fund_based_exposure`, not a combined fund+non-fund total.** The generator never applies NPA classification to the non-fund book ("non-fund book: no NPA overlay" — `generate_synthetic_data.py`). A combined denominator would understate the ratio.
- **Window metrics in `TRANSACTIONS_SV` reference the base metric by its bare name** (`SUM(total_amount) OVER (...)`, not `SUM(AMOUNT) OVER (...)`), and `AMOUNT` is deliberately **not** declared under `FACTS` — this follows the `window_metrics` pattern's own documented gotcha (`PARTITION BY EXCLUDING` fails on any metric built directly from a `FACTS` column).
