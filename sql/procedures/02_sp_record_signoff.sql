-- SP_RECORD_SIGNOFF — the maker-checker sign-off, finally wired up. Real gap
-- found during RBAC verification (sql/rbac/verification_results.md) and the
-- production-deployment/eval work around it: sql/rbac/04_officer_signoff.sql's
-- header comment always described a sign-off as "a new row... RUN_ID
-- referencing the run being signed off on," but nothing ever actually wrote
-- one — SP_WRITE_AUDIT_LOG (sql/procedures/01_*.sql) only ever leaves
-- HUMAN_DECISION/SIGNOFF_BY/SIGNOFF_AT NULL, by design, since it writes the
-- run being signed off on, not the sign-off itself.
--
-- STAGE is a required parameter here, not looked up from the original row,
-- deliberately: OFFICER_SIGNOFF has no SELECT grant on AUDIT_LOG at all
-- (verified live, sql/rbac/verification_results.md section 4) and this
-- procedure's EXECUTE AS OWNER identity is OFFICER_SIGNOFF itself after
-- ownership transfer below -- so it must not need to read AUDIT_LOG to do
-- its job, the same insert-only, no-read-back boundary
-- sql/rbac/03_audit_insert.sql's comment describes for AUDIT_INSERT. The
-- caller (a compliance officer looking at the specific run on screen while
-- deciding to sign off on it) already knows the stage; passing it in avoids
-- granting a new read privilege just to look up one column.

USE ROLE ACCOUNTADMIN;
USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE PROCEDURE SP_RECORD_SIGNOFF(
  SIGNOFF_FOR_RUN_ID VARCHAR, RUN_ID VARCHAR, STAGE VARCHAR,
  SIGNOFF_BY VARCHAR, HUMAN_DECISION VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Records a maker-checker sign-off as a NEW AUDIT_LOG row (never an UPDATE of the run being signed off on). SIGNOFF_FOR_RUN_ID links back to the original RUN_ID. STAGE is supplied by the caller, not looked up, so this stays insert-only -- no SELECT grant on AUDIT_LOG needed to call it.'
AS
$$
BEGIN
  INSERT INTO PRAMAN.CORE.AUDIT_LOG
    (RUN_ID, APP_USER, STAGE, HUMAN_DECISION, SIGNOFF_BY, SIGNOFF_AT, SIGNOFF_FOR_RUN_ID, IS_EVAL)
  SELECT :RUN_ID, :SIGNOFF_BY, :STAGE, :HUMAN_DECISION, :SIGNOFF_BY, CURRENT_TIMESTAMP(), :SIGNOFF_FOR_RUN_ID, FALSE;
  RETURN 'OK';
END;
$$;

-- Same pattern as SP_WRITE_AUDIT_LOG: OFFICER_SIGNOFF can't CREATE PROCEDURE
-- (sql/rbac/04_officer_signoff.sql grants it nothing but INSERT on AUDIT_LOG
-- + USAGE on DB/schema), so this is created under an admin role and handed
-- off. Ownership transfers directly to OFFICER_SIGNOFF (not a separate USAGE
-- grant to a different caller role, unlike SP_WRITE_AUDIT_LOG) since
-- sign-off is that role's own action, not something another role performs
-- on its behalf -- owning the procedure already carries USAGE.
GRANT OWNERSHIP ON PROCEDURE SP_RECORD_SIGNOFF(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR)
  TO ROLE OFFICER_SIGNOFF COPY CURRENT GRANTS;
