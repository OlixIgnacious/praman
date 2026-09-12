# Verifying the RBAC boundaries actually hold

`sql/rbac/`'s four grant scripts (`01_analyst_read.sql` through `04_officer_signoff.sql`) were written and applied to Snowflake, but until now nobody had actually tried the operations they're supposed to deny and watched Snowflake reject them. Every eval run to date (`eval/run_eval.md`) tests the **agent's** behavior; this tests whether the **platform** actually enforces the boundaries the agent's design depends on — "append-only by grant, not convention" and the maker-checker role split are the compliance-credibility core of the whole pitch, and they've been asserted by reading the grant SQL, not proven live.

**Prerequisite:** re-run `01_analyst_read.sql` through `04_officer_signoff.sql` first if you haven't since this file was written — they now each grant `USAGE ON WAREHOUSE COMPUTE_WH`, a real gap found while writing this runbook (none of the four roles could execute *any* query at all before this, since Snowflake requires warehouse access to run a query regardless of table-level grants).

Run everything below as `ACCOUNTADMIN` (or another role that can `USE ROLE` into all four — they're reachable transitively since `00_roles.sql` grants all four to `SYSADMIN`). Switching `USE ROLE` mid-session correctly narrows your active privileges to exactly that role's own grants for every statement that follows, regardless of what other roles your user also holds — that's what makes this a valid test of each role in isolation, not a workaround.

## Format

For each numbered check: run the statement, compare against "Expected," record what actually happened. A check that succeeds when it should have failed (or vice versa) is a finding, not a footnote — write it up the same way `eval/results.md` writes up a miss, with the actual error text or actual result.

## 0. Ownership check — do first, informs how to read "no UPDATE/DELETE" below

```sql
SHOW GRANTS ON TABLE PRAMAN.CORE.AUDIT_LOG;
SHOW GRANTS ON TABLE PRAMAN.CORE.LINE_ITEM_MAP;
```

Read the `OWNER` grant in the output. Whichever role owns a table gets full privileges on it *through ownership*, independent of any explicit `GRANT UPDATE`/`GRANT DELETE` — this is inherent to how Snowflake ownership works, not a gap in this project's RBAC design. If `ACCOUNTADMIN` (or `SYSADMIN`) owns `AUDIT_LOG`, then `CLAUDE.md`'s "no role, including admin, gets update/delete" claim needs an honest caveat for the pitch: true for every functional/analyst-facing role, not literally true for the account's top-level admin, which retains implicit override the way it would over any Snowflake object. Note the actual owner here before running section 3 below, so a denial or success there is interpreted correctly.

## 1. `ANALYST_READ` — read-only, `CORE` only

```sql
USE ROLE ANALYST_READ;
USE WAREHOUSE COMPUTE_WH;

-- 1a. Expected: succeed
SELECT COUNT(*) FROM PRAMAN.CORE.RULE_CORPUS;
SELECT COUNT(*) FROM PRAMAN.CORE.LINE_ITEM_MAP;
SELECT COUNT(*) FROM PRAMAN.CORE.GL_ENTRIES;

-- 1b. Expected: fail (no write grant anywhere for this role)
UPDATE PRAMAN.CORE.LINE_ITEM_MAP SET STATUS = 'approved' WHERE LINE_ITEM_ID = 'PILLAR3.IND_NPA.GROSS';
INSERT INTO PRAMAN.CORE.AUDIT_LOG (RUN_ID, APP_USER, STAGE, IS_EVAL) VALUES ('RBAC-TEST-SHOULD-FAIL', 'rbac_test', '0', TRUE);

-- 1c. Expected: fail -- this is the eval-answer-key isolation the entire
-- eval's validity depends on. Should fail on missing SCHEMA USAGE, not just
-- table SELECT -- a stronger denial than table-level would be.
SELECT COUNT(*) FROM PRAMAN.EVAL.INJECTED_CASES;
```

## 2. `GOVERNANCE_WRITE` — approve `LINE_ITEM_MAP`, propose `RULE_CORPUS`, nothing on `AUDIT_LOG`

```sql
USE ROLE GOVERNANCE_WRITE;
USE WAREHOUSE COMPUTE_WH;

-- 2a. Expected: succeed -- INSERT a harmless, clearly-tagged test row, then
-- UPDATE it (proves both grants), then leave it for cleanup in section 4.
INSERT INTO PRAMAN.CORE.LINE_ITEM_MAP
  (LINE_ITEM_ID, REPORT_NAME, SOURCE_TABLE, SOURCE_COLUMN, STATUS, VALID_FROM)
VALUES
  ('RBAC_TEST.ROW', 'RBAC verification -- delete me', 'RBAC_TEST', 'RBAC_TEST', 'proposed', CURRENT_DATE());
UPDATE PRAMAN.CORE.LINE_ITEM_MAP SET STATUS = 'approved', APPROVED_BY = 'rbac_test' WHERE LINE_ITEM_ID = 'RBAC_TEST.ROW';

-- 2b. Expected: fail on all three -- GOVERNANCE_WRITE has no grant on AUDIT_LOG
-- itself (only on the AUDIT_EVIDENCE_PACK view, tested in 2c)
SELECT COUNT(*) FROM PRAMAN.CORE.AUDIT_LOG;
INSERT INTO PRAMAN.CORE.AUDIT_LOG (RUN_ID, APP_USER, STAGE, IS_EVAL) VALUES ('RBAC-TEST-SHOULD-FAIL-2', 'rbac_test', '0', TRUE);
DELETE FROM PRAMAN.CORE.LINE_ITEM_MAP WHERE LINE_ITEM_ID = 'RBAC_TEST.ROW'; -- no DELETE grant, even on a row this role itself inserted

-- 2c. Expected: succeed -- the one AUDIT_LOG-adjacent thing this role can read
SELECT COUNT(*) FROM PRAMAN.CORE.AUDIT_EVIDENCE_PACK;

-- 2d. Expected: fail, same as 1c
SELECT COUNT(*) FROM PRAMAN.EVAL.INJECTED_CASES;
```

## 3. `AUDIT_INSERT` — insert-only, cannot even read its own writes

```sql
USE ROLE AUDIT_INSERT;
USE WAREHOUSE COMPUTE_WH;

-- 3a. Expected: succeed
INSERT INTO PRAMAN.CORE.AUDIT_LOG (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, IS_EVAL)
VALUES ('RBAC-TEST-AUDIT-INSERT-01', 'rbac_test', '0', '[RBAC_TEST] role-boundary verification -- audit_insert', TRUE);

-- 3b. Expected: fail on all three -- deliberately no SELECT/UPDATE/DELETE for
-- this role at all, per 03_audit_insert.sql's own header comment
SELECT COUNT(*) FROM PRAMAN.CORE.AUDIT_LOG;
UPDATE PRAMAN.CORE.AUDIT_LOG SET HUMAN_DECISION = 'accepted' WHERE RUN_ID = 'RBAC-TEST-AUDIT-INSERT-01';
DELETE FROM PRAMAN.CORE.AUDIT_LOG WHERE RUN_ID = 'RBAC-TEST-AUDIT-INSERT-01';

-- 3c. Expected: fail
UPDATE PRAMAN.CORE.LINE_ITEM_MAP SET STATUS = 'approved' WHERE LINE_ITEM_ID = 'PILLAR3.IND_NPA.GROSS';
```

## 4. `OFFICER_SIGNOFF` — insert-only, records a sign-off as a new row

```sql
USE ROLE OFFICER_SIGNOFF;
USE WAREHOUSE COMPUTE_WH;

-- 4a. Expected: succeed
INSERT INTO PRAMAN.CORE.AUDIT_LOG (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, HUMAN_DECISION, SIGNOFF_BY, SIGNOFF_AT, IS_EVAL)
VALUES ('RBAC-TEST-OFFICER-SIGNOFF-01', 'rbac_test', '2', '[RBAC_TEST] role-boundary verification -- officer_signoff', 'accepted', 'rbac_test_officer', CURRENT_TIMESTAMP(), TRUE);

-- 4b. Expected: fail, same as AUDIT_INSERT -- this role is deliberately
-- identical in shape (see 04_officer_signoff.sql's header comment)
SELECT COUNT(*) FROM PRAMAN.CORE.AUDIT_LOG;
UPDATE PRAMAN.CORE.AUDIT_LOG SET HUMAN_DECISION = 'escalated' WHERE RUN_ID = 'RBAC-TEST-OFFICER-SIGNOFF-01';
UPDATE PRAMAN.CORE.LINE_ITEM_MAP SET STATUS = 'approved' WHERE LINE_ITEM_ID = 'PILLAR3.IND_NPA.GROSS';
```

## 5. Cross-check every role's actual grant surface

```sql
SHOW GRANTS TO ROLE ANALYST_READ;
SHOW GRANTS TO ROLE GOVERNANCE_WRITE;
SHOW GRANTS TO ROLE AUDIT_INSERT;
SHOW GRANTS TO ROLE OFFICER_SIGNOFF;
```

Confirm: zero rows reference `PRAMAN.EVAL` for any of the four (the eval-isolation guarantee, checked directly rather than inferred from "we didn't write a grant for it" -- a role could in principle gain incidental access some other way, e.g. `PUBLIC` role grants or an inherited future-grant policy neither of us has reason to expect but haven't ruled out either).

## 6. Cleanup

```sql
USE ROLE GOVERNANCE_WRITE;
DELETE FROM PRAMAN.CORE.LINE_ITEM_MAP WHERE LINE_ITEM_ID = 'RBAC_TEST.ROW'; -- expected to fail (2b already proved this) -- use ACCOUNTADMIN instead
USE ROLE ACCOUNTADMIN;
DELETE FROM PRAMAN.CORE.LINE_ITEM_MAP WHERE LINE_ITEM_ID = 'RBAC_TEST.ROW';
```

The three `RBAC-TEST-*` rows left in `AUDIT_LOG` (3a, 4a) are expected to stay forever — that's the point of testing an append-only table. They're `IS_EVAL = TRUE`, so `AUDIT_EVIDENCE_PACK` already excludes them from anything a reviewer would see; no cleanup needed or possible.

## What to report back

For each of 1a–5, a line: **expected** vs. **actual** (paste the exact success result or the exact Snowflake error text on a denial). Anything that didn't match expected is the actual finding — report those first and in full, since that's what turns "we wrote RBAC" into "we verified RBAC."
