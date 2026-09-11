# DDL — run order

Numbered for dependency order (FK targets must exist before the table that references them). Snowflake doesn't enforce FK constraints at write time, but ordering still matters because `CREATE TABLE ... REFERENCES <table>` fails if `<table>` doesn't exist yet.

1. `00_database_and_schema.sql` — `PRAMAN.CORE`, `PRAMAN.EVAL`
2. `01_rule_corpus.sql`
3. `02_line_item_map.sql` (→ `RULE_CORPUS`)
4. `03_counterparties.sql`
5. `04_positions.sql` (→ `COUNTERPARTIES`)
6. `05_injected_cases.sql` (in `EVAL` — isolated, see file comment)
7. `06_gl_entries.sql` (→ `COUNTERPARTIES`, `POSITIONS`)
8. `07_transactions.sql` (→ `COUNTERPARTIES`)
9. `08_divergence_disclosures.sql` (→ `LINE_ITEM_MAP`)
10. `09_audit_log.sql`
11. `10_eval_results.sql` (in `EVAL` — → `INJECTED_CASES`)

RBAC grants (`sql/rbac/`, not yet written) run after this — in particular, the `EVAL` schema must never grant `SELECT` to the role Skills run as.
