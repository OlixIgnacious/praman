# Exports

Compliance/audit-facing views over data this project already governs — read-only, run after the objects they read from already exist.

1. `01_audit_evidence_pack.sql` — `AUDIT_EVIDENCE_PACK`, the evidence-pack export from `AUDIT_LOG` (`architecture.md`'s Evaluation architecture: "Compliance, internal audit, evidence pack export").

## Why a plain view, not an automated pipeline

Every SQL change in this project runs by hand, in an interactive `cortex` session (`NOTES.md`'s standing convention) — there's no scheduled-task or unload infrastructure anywhere else in this repo to hang an automated export on. `AUDIT_EVIDENCE_PACK` is a `SELECT`-able view; a reviewer runs a query against it and downloads the result (CSV, from Snowsight or the `cortex` CLI) themselves. A `COPY INTO @stage` unload would be the natural next step if this ever needs to leave Snowflake as a file on a schedule — not needed yet, and not built pre-emptively.

## `AUDIT_LOG` had no reader at all before this

Check the four RBAC roles (`sql/rbac/`): `ANALYST_READ` and `GOVERNANCE_WRITE` were never granted `SELECT` on `AUDIT_LOG`, and `AUDIT_INSERT`/`OFFICER_SIGNOFF` are deliberately insert-only by their own documented design intent (their header comments in `sql/rbac/03_audit_insert.sql`/`04_officer_signoff.sql` — granting either of them read access here would undo the one property that makes "insert-only" an enforced boundary rather than a policy statement). `01_audit_evidence_pack.sql` grants `SELECT` on the view to `GOVERNANCE_WRITE` — the closest existing fit (this project's other control/oversight role), flagged as imperfect in that file's own header comment. No role is actually "the compliance officer/examiner reviewing evidence" today; a dedicated role is the architecturally correct long-term answer, left as an open RBAC decision rather than added unilaterally here.

## A related gap this file surfaces but doesn't fix

`sql/rbac/04_officer_signoff.sql`'s header comment describes a sign-off as a new row with "`RUN_ID` referencing the run being signed off on" — but `RUN_ID` is `AUDIT_LOG`'s primary key, so a sign-off row can't both have its own unique `RUN_ID` and store the original run's `RUN_ID` in that same column. There's no separate linking column today, and no procedure yet writes a sign-off row at all — `SP_WRITE_AUDIT_LOG` (the only procedure that exists) always leaves `HUMAN_DECISION`/`SIGNOFF_BY`/`SIGNOFF_AT` `NULL`. `AUDIT_EVIDENCE_PACK` surfaces those columns as-is; today every real row has them `NULL`. Fixing this (e.g. adding a `SIGNOFF_FOR_RUN_ID` column and a corresponding write procedure) is real future work, not something this export file resolves.
