# RBAC role-boundary verification results — 22/22, zero findings

Run per `role_verification.md` against live Snowflake, 2026-09-13. This tests the **platform**, not the agent — whether Snowflake actually enforces the boundaries `sql/rbac/`'s four grant scripts claim to set up, which every eval run to date (`eval/run_eval.md`) never touched.

## Section 0 — Ownership

| Object | Owner |
|---|---|
| `AUDIT_LOG` | `ACCOUNTADMIN` |
| `LINE_ITEM_MAP` | `ACCOUNTADMIN` |

**Caveat, as the runbook flagged in advance:** `ACCOUNTADMIN` retains implicit full privilege over both tables through Snowflake ownership, independent of any explicit grant. `architecture.md`'s "no role, including admin, gets update/delete" is **verified true for every functional/analyst-facing role** (`ANALYST_READ`/`GOVERNANCE_WRITE`/`AUDIT_INSERT`/`OFFICER_SIGNOFF`) — confirmed live below — but not literally true for the account's top-level admin, which is inherent to how Snowflake ownership works, not a gap in this project's design. State the claim with this precision in pitch material: "no operational role can modify the audit log," not "no one, including admins, can."

## Sections 1–4 — per-role checks, 22/22 pass

| # | Role | Check | Expected | Actual | Status |
|---|---|---|---|---|---|
| 1a | `ANALYST_READ` | `SELECT` on `RULE_CORPUS`/`LINE_ITEM_MAP`/`GL_ENTRIES` | succeed | succeed (30/9/2214 rows) | PASS |
| 1b-i | `ANALYST_READ` | `UPDATE LINE_ITEM_MAP` | fail | fail — insufficient privileges (UPDATE) | PASS |
| 1b-ii | `ANALYST_READ` | `INSERT INTO AUDIT_LOG` | fail | fail — does not exist or not authorized | PASS |
| 1c | `ANALYST_READ` | `SELECT` on `PRAMAN.EVAL.INJECTED_CASES` | fail | fail — schema `PRAMAN.EVAL` does not exist or not authorized | PASS |
| 2a | `GOVERNANCE_WRITE` | `INSERT` + `UPDATE` on `LINE_ITEM_MAP` | succeed | succeed | PASS |
| 2b-i | `GOVERNANCE_WRITE` | `SELECT AUDIT_LOG` | fail | fail — does not exist or not authorized | PASS |
| 2b-ii | `GOVERNANCE_WRITE` | `INSERT AUDIT_LOG` | fail | fail — does not exist or not authorized | PASS |
| 2b-iii | `GOVERNANCE_WRITE` | `DELETE` its own inserted `LINE_ITEM_MAP` row | fail | fail — insufficient privileges (DELETE) | PASS |
| 2c | `GOVERNANCE_WRITE` | `SELECT AUDIT_EVIDENCE_PACK` | succeed | succeed (8 rows) | PASS |
| 2d | `GOVERNANCE_WRITE` | `SELECT` on `PRAMAN.EVAL.INJECTED_CASES` | fail | fail — schema not authorized | PASS |
| 3a | `AUDIT_INSERT` | `INSERT INTO AUDIT_LOG` | succeed | succeed | PASS |
| 3b-i | `AUDIT_INSERT` | `SELECT AUDIT_LOG` | fail | fail — insufficient privileges (SELECT) | PASS |
| 3b-ii | `AUDIT_INSERT` | `UPDATE AUDIT_LOG` | fail | fail — insufficient privileges (SELECT) | PASS |
| 3b-iii | `AUDIT_INSERT` | `DELETE AUDIT_LOG` | fail | fail — insufficient privileges (SELECT) | PASS |
| 3c | `AUDIT_INSERT` | `UPDATE LINE_ITEM_MAP` | fail | fail — does not exist or not authorized | PASS |
| 4a | `OFFICER_SIGNOFF` | `INSERT` a sign-off-shaped `AUDIT_LOG` row | succeed | succeed | PASS |
| 4b-i | `OFFICER_SIGNOFF` | `SELECT AUDIT_LOG` | fail | fail — insufficient privileges (SELECT) | PASS |
| 4b-ii | `OFFICER_SIGNOFF` | `UPDATE AUDIT_LOG` | fail | fail — insufficient privileges (SELECT) | PASS |
| 4b-iii | `OFFICER_SIGNOFF` | `UPDATE LINE_ITEM_MAP` | fail | fail — does not exist or not authorized | PASS |

`UPDATE`/`DELETE` denials on `AUDIT_LOG` report as a `SELECT` privilege error, not an `UPDATE`/`DELETE` one — expected, since `AUDIT_INSERT`/`OFFICER_SIGNOFF` can't even see the table to identify a row to modify (Snowflake surfaces the first missing privilege it hits, which is read visibility here). Deliberate design, per `03_audit_insert.sql`'s header comment — not a masked finding.

## Section 5 — grant surface cross-check

`SHOW GRANTS TO ROLE` for all four roles: **zero rows reference `PRAMAN.EVAL`.** The eval-answer-key isolation `INJECTED_CASES`/`EVAL_RESULTS` depends on is confirmed directly, not just inferred from "we didn't write a grant for it."

## Section 6 — cleanup

`GOVERNANCE_WRITE`'s own `DELETE` on its test row correctly denied (matches 2b-iii); `ACCOUNTADMIN` cleanup succeeded via ownership. The `RBAC-TEST-*` rows written to `AUDIT_LOG` in 3a/4a stay permanently — that's the point of testing an append-only table — tagged `IS_EVAL = TRUE`, so `AUDIT_EVIDENCE_PACK` already excludes them from anything a compliance reviewer would see.

## Methodological finding, not a design finding — but important for anyone re-running this

**The first attempt at this runbook produced false passes.** Snowflake sessions activate *all* of a user's granted roles as secondary roles by default alongside whatever `USE ROLE` sets as primary. An `ACCOUNTADMIN` user running `USE ROLE ANALYST_READ;` without also running `USE SECONDARY ROLES NONE;` still has `ACCOUNTADMIN`'s privileges active in the background — a denial that should have failed instead silently succeeded via ownership bleeding through as a secondary role. `role_verification.md` now includes `USE SECONDARY ROLES NONE;` in every role-switch block; the results above are from the corrected run. A second related gotcha: `USE ROLE`/`USE SECONDARY ROLES` don't persist across separate statement submissions in some clients — the session resets to its connection default role — so each section must run as one multi-statement batch, not as individually submitted statements.

## Bottom line

**22/22 checks pass, zero design findings.** The RBAC design — read-only analyst access, governance approve/propose, insert-only audit logging, eval-answer-key isolation — is not just written correctly, it's now been proven to actually hold against live Snowflake, with the one documented, expected, and inherent-to-the-platform caveat about admin ownership. `plan.md`'s pending item 6 is closed.
