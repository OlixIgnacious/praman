# Pending manual runs

Snowflake changes written but not yet executed — non-interactive `cortex exec` auto-denies mutating SQL, so these run in an interactive `cortex` session instead, where you approve each statement.

## Done

- Semantic Views, the shared detector, `SP_WRITE_AUDIT_LOG`, and **`SIGNAL_ASSURE_AGENT`** — all deployed and verified live. 5/5 test questions passed (3 Stage 0, 2 Stage 2), including the two that mattered most: the AML-adjacent question correctly flagged for compliance review rather than a verdict, and the `LINE_ITEM_MAP` validation question correctly returned "no approved mapping / pending governance approval" instead of silently computing a value. `AUDIT_LOG` got exactly one correct row per test. `TRANSACTIONS_AGENT` (the spike) has been dropped from Snowflake and its local artifacts removed. Days 9–12's Cortex Agent work is done.

Three real Cortex Agent platform limitations found and fixed during this deployment (now reflected in the source files, not just here):
1. **`generic` tool `input_schema` doesn't support `array` types** in practice — `retrieved_rule_chunk_ids` changed from `ARRAY` to a comma-delimited `VARCHAR`, parsed back to an array inside `SP_WRITE_AUDIT_LOG` via `SPLIT()`.
2. **`ARRAY_CONSTRUCT()`/`SPLIT()` aren't valid inside a plain `VALUES` clause** in this context — the procedure's `INSERT` switched from `VALUES` to `INSERT ... SELECT`.
3. **The agent drops tool-call arguments it considers optional**, which breaks positional-signature matching on an 8-argument procedure call — fixed by making all 8 `input_schema` properties `required` (Stage-inapplicable fields get an explicit empty-string convention instead of being omitted).

## Nothing currently pending

Next up per `plan.md` (Days 12–15): wire Stage 0 and Stage 2 as the two "live" paths for the demo, plus start on Stage 1's ingestion-pipeline-backed slice and Stage 3's scripted lineage walkthrough — both still custom-backend territory, not CoWork/Cortex Agent.
