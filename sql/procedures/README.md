# Procedures — run order

Run after `sql/rbac/` (the owning role must exist) and `sql/ddl/` (the tables the procedure writes to must exist).

1. `01_sp_write_audit_log.sql` — `SP_WRITE_AUDIT_LOG`, ownership transferred to `AUDIT_INSERT`
2. `02_sp_record_signoff.sql` — `SP_RECORD_SIGNOFF`, ownership transferred to `OFFICER_SIGNOFF`

## Why a procedure instead of a direct grant

`AUDIT_INSERT` is the only role with `INSERT` on `AUDIT_LOG` (`sql/rbac/03_audit_insert.sql`) — deliberately, so no other role can write audit rows directly. The Cortex Agent built in `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml` runs as `ANALYST_READ`, which has no `INSERT` on `AUDIT_LOG` and shouldn't get one. `SP_WRITE_AUDIT_LOG` bridges this the same way the rest of this project's RBAC does — through a narrow, single-purpose grant, not by widening `ANALYST_READ`'s privileges:

- The procedure is declared `EXECUTE AS OWNER`, so it runs with its *owner's* privileges regardless of which role calls it.
- Ownership is transferred to `AUDIT_INSERT` after creation (a role can't `CREATE PROCEDURE` without that grant, so it has to be created under an admin role first, then handed off).
- `ANALYST_READ` gets `USAGE` on the procedure — enough to call it, nothing more. It still cannot `SELECT`/`UPDATE`/`DELETE` on `AUDIT_LOG` directly.

This preserves the same "insert-only, no read-back" boundary `sql/rbac/03_audit_insert.sql`'s comment describes — reached through a procedure call instead of a direct table grant, because the caller here is an LLM-orchestrated Cortex Agent tool, not a human-issued statement.

## `RETRIEVED_RULE_CHUNK_IDS` is `VARCHAR`, not `ARRAY` — a real deployment fix

Originally designed with `AUDIT_LOG.RETRIEVED_RULE_CHUNK_IDS`'s native `ARRAY` type carried straight through the procedure signature. Deploying the agent that calls this procedure surfaced two real platform limitations, fixed live rather than in this doc's original design:

- A Cortex Agent `generic` tool's `input_schema` doesn't support `array`-typed properties in practice — so the tool sends chunk IDs as a comma-delimited string, and the parameter here is `VARCHAR`.
- `ARRAY_CONSTRUCT()`/`SPLIT()` aren't valid inside a plain `INSERT ... VALUES` clause in this context — the procedure builds the row with `INSERT ... SELECT` instead, so `SPLIT(:RETRIEVED_RULE_CHUNK_IDS, ',')` can convert the string back to an `ARRAY` for the actual `AUDIT_LOG` column.

Empty/NULL input is treated as "no chunks cited" (`ARRAY_CONSTRUCT()`), not an error — Stage 0 calls always pass an empty string here since Stage 0's citation type is query + data lineage, not a rule chunk.

## `IS_EVAL` — a 9th parameter, added for the Days 15–17 eval harness

`architecture.md`'s Evaluation architecture requires eval traffic to write `AUDIT_LOG.IS_EVAL = TRUE` so it never contaminates what a compliance reviewer sees (`AUDIT_EVIDENCE_PACK`, `sql/exports/`, explicitly excludes `IS_EVAL = TRUE` rows). The original procedure hardcoded `FALSE`. Since `SIGNAL_ASSURE_AGENT` calls `write_audit_log` unconditionally every turn, running eval questions through the live agent without this fix would have written them into the real audit trail as if they were live analyst traffic — the exact contamination `architecture.md` says must not happen. Fixed by adding `IS_EVAL VARCHAR` (`'TRUE'`/`'FALSE'`, same non-native-type reasoning as `RETRIEVED_RULE_CHUNK_IDS` above), sourced by the agent's orchestration from a `[EVAL]` prompt marker (`cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml`) — see `eval/run_eval.md` for the actual eval questions.

**Re-deploying this procedure requires an explicit `DROP` first**, not just `CREATE OR REPLACE`: Snowflake identifies a procedure by name *and* argument signature, so adding a 9th parameter creates a second overload rather than replacing the 8-arg one. The file drops the old signature explicitly. Also runs as `ACCOUNTADMIN` now, not `SECURITYADMIN` — dropping an object already owned by `AUDIT_INSERT` is a different privilege question than the original `MANAGE GRANTS`-based ownership transfer, and `ACCOUNTADMIN` removes the ambiguity.

## `SP_RECORD_SIGNOFF` — closes a real gap, `AUDIT_LOG.SIGNOFF_FOR_RUN_ID`

`sql/rbac/04_officer_signoff.sql`'s header comment always described a sign-off as "a new row... `RUN_ID` referencing the run being signed off on," but nothing ever actually wrote one — `SP_WRITE_AUDIT_LOG` always leaves `HUMAN_DECISION`/`SIGNOFF_BY`/`SIGNOFF_AT` `NULL` by design, since it writes the run *being* signed off on, not the sign-off itself. Found doing RBAC verification (`sql/rbac/verification_results.md`) and flagged in `sql/exports/01_audit_evidence_pack.sql`'s original header comment as a known gap.

`AUDIT_LOG` gained `SIGNOFF_FOR_RUN_ID` (`sql/ddl/09_audit_log.sql`) — the actual linking column that comment assumed existed — and `SP_RECORD_SIGNOFF` is what writes it: a new row with `HUMAN_DECISION`/`SIGNOFF_BY`/`SIGNOFF_AT` populated and `SIGNOFF_FOR_RUN_ID` pointing at the original run.

**Deliberately different from `SP_WRITE_AUDIT_LOG` in one way:** `STAGE` is a required parameter, not looked up from the original row. `OFFICER_SIGNOFF` has no `SELECT` grant on `AUDIT_LOG` at all (verified live — `sql/rbac/verification_results.md` section 4), and this procedure's `EXECUTE AS OWNER` identity is `OFFICER_SIGNOFF` itself, so it must not need to read `AUDIT_LOG` to do its job — the same insert-only, no-read-back boundary `03_audit_insert.sql`'s comment describes. The caller (a compliance officer looking at the specific run on screen while deciding to sign off) already knows the stage.

**Also different from `SP_WRITE_AUDIT_LOG`'s ownership pattern:** ownership transfers straight to `OFFICER_SIGNOFF` with no separate `USAGE` grant to a different caller role, since sign-off is `OFFICER_SIGNOFF`'s own action — owning the procedure already carries `USAGE`.

`AUDIT_EVIDENCE_PACK` (`sql/exports/01_audit_evidence_pack.sql`) was updated to `LEFT JOIN` a run against its most recent sign-off row via `SIGNOFF_FOR_RUN_ID`, rather than expecting one row to carry both — and excludes standalone sign-off rows from appearing as their own "runs" in the pack.

## Run

`01_sp_write_audit_log.sql` (9-arg, `IS_EVAL` included) is deployed and verified live — see `eval/results.md`'s three eval runs, all correctly tagged. `02_sp_record_signoff.sql` is written; exact redeploy commands queued in `NOTES.md`. `01_sp_write_audit_log.sql`'s header comment has the full ownership-transfer rationale for that procedure.
