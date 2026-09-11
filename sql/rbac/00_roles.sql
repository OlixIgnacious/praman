-- Four functional roles per architecture.md's "Deployment & security" section.
-- Wired into the SYSADMIN hierarchy so they're manageable through the normal
-- role tree instead of orphaned custom roles. Run as SECURITYADMIN/ACCOUNTADMIN.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ANALYST_READ
  COMMENT = 'Read RULE_CORPUS/LINE_ITEM_MAP and the transaction/position/counterparty tables via Cortex Analyst/Search';

CREATE ROLE IF NOT EXISTS GOVERNANCE_WRITE
  COMMENT = 'Approve LINE_ITEM_MAP changes, commit new RULE_CORPUS versions';

CREATE ROLE IF NOT EXISTS AUDIT_INSERT
  COMMENT = 'Insert-only on AUDIT_LOG — every Skill invocation. No UPDATE/DELETE grant exists on this table for any role.';

CREATE ROLE IF NOT EXISTS OFFICER_SIGNOFF
  COMMENT = 'Insert-only on AUDIT_LOG — records a maker-checker sign-off as a new row, never an UPDATE of the original';

GRANT ROLE ANALYST_READ TO ROLE SYSADMIN;
GRANT ROLE GOVERNANCE_WRITE TO ROLE SYSADMIN;
GRANT ROLE AUDIT_INSERT TO ROLE SYSADMIN;
GRANT ROLE OFFICER_SIGNOFF TO ROLE SYSADMIN;
