# RBAC — run order

Run after all of `sql/ddl/` (these scripts grant on objects that must already exist). Requires a role with `MANAGE GRANTS` / `CREATE ROLE` privilege (e.g. `SECURITYADMIN` or `ACCOUNTADMIN`).

1. `00_roles.sql` — creates the four functional roles and wires them into the `SYSADMIN` hierarchy
2. `01_analyst_read.sql` — `ANALYST_READ`
3. `02_governance_write.sql` — `GOVERNANCE_WRITE`
4. `03_audit_insert.sql` — `AUDIT_INSERT`
5. `04_officer_signoff.sql` — `OFFICER_SIGNOFF`

## Design

Four roles, per `architecture.md`'s "Deployment & security" section:

| Role | Purpose | Grants |
|---|---|---|
| `ANALYST_READ` | Every analyst; queries via Cortex Analyst / Cortex Search | `SELECT` on all `PRAMAN.CORE` tables Stage 0/1/2/3 read (`RULE_CORPUS`, `LINE_ITEM_MAP`, `COUNTERPARTIES`, `POSITIONS`, `GL_ENTRIES`, `TRANSACTIONS`, `DIVERGENCE_DISCLOSURES`) |
| `GOVERNANCE_WRITE` | Approves `LINE_ITEM_MAP` changes, commits new rule versions | `SELECT`/`INSERT`/`UPDATE` on `LINE_ITEM_MAP`, `SELECT`/`INSERT` on `RULE_CORPUS` |
| `AUDIT_INSERT` | Every Skill invocation logs here | `INSERT` only on `AUDIT_LOG` — no role is ever granted `UPDATE`/`DELETE` on it, anywhere in this repo |
| `OFFICER_SIGNOFF` | Records the maker-checker sign-off decision | `INSERT` only on `AUDIT_LOG` — a sign-off is a **new** row (`HUMAN_DECISION`, `SIGNOFF_BY`, `SIGNOFF_AT` populated), never an `UPDATE` of the run's original row, so `AUDIT_LOG` stays genuinely append-only end to end |

**`PRAMAN.EVAL` gets no grants in this directory, deliberately.** `INJECTED_CASES` is the eval answer key — no role a Skill runs as may ever read it (see `sql/ddl/05_injected_cases.sql`). Running the eval harness itself is an admin-session concern for the prototype, not one of these four roles; a dedicated eval-runner role is a roadmap item if this goes beyond solo/hackathon scope.

**No warehouse grants here.** `USAGE` on a compute warehouse isn't included since no warehouse is created anywhere in `sql/ddl/` — add `GRANT USAGE ON WAREHOUSE <name> TO ROLE <role>;` once the account's actual warehouse name is decided, rather than guessing one here.

**Assigning roles to users/service accounts is left as a template**, not executed — see the commented `GRANT ROLE ... TO USER ...` line at the bottom of each grant script. Fill in the actual username (interactive analyst) or service account name (backend's keypair-auth identity) before running.
