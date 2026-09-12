# Procedures — run order

Run after `sql/rbac/` (the owning role must exist) and `sql/ddl/` (the tables the procedure writes to must exist).

1. `01_sp_write_audit_log.sql` — `SP_WRITE_AUDIT_LOG`, ownership transferred to `AUDIT_INSERT`

## Why a procedure instead of a direct grant

`AUDIT_INSERT` is the only role with `INSERT` on `AUDIT_LOG` (`sql/rbac/03_audit_insert.sql`) — deliberately, so no other role can write audit rows directly. The Cortex Agent built in `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml` runs as `ANALYST_READ`, which has no `INSERT` on `AUDIT_LOG` and shouldn't get one. `SP_WRITE_AUDIT_LOG` bridges this the same way the rest of this project's RBAC does — through a narrow, single-purpose grant, not by widening `ANALYST_READ`'s privileges:

- The procedure is declared `EXECUTE AS OWNER`, so it runs with its *owner's* privileges regardless of which role calls it.
- Ownership is transferred to `AUDIT_INSERT` after creation (a role can't `CREATE PROCEDURE` without that grant, so it has to be created under an admin role first, then handed off).
- `ANALYST_READ` gets `USAGE` on the procedure — enough to call it, nothing more. It still cannot `SELECT`/`UPDATE`/`DELETE` on `AUDIT_LOG` directly.

This preserves the same "insert-only, no read-back" boundary `sql/rbac/03_audit_insert.sql`'s comment describes — reached through a procedure call instead of a direct table grant, because the caller here is an LLM-orchestrated Cortex Agent tool, not a human-issued statement.

## Run

```sql
-- As SECURITYADMIN or another role with CREATE PROCEDURE on PRAMAN.CORE:
-- (see 01_sp_write_audit_log.sql for the full CREATE + ownership transfer + grant)
```

Add the exact run command to `NOTES.md` before running — this project's SQL executes in an interactive `cortex` session, not headlessly (non-interactive `cortex exec` auto-denies mutating SQL).
