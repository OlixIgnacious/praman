-- SP_WRITE_AUDIT_LOG — the bridge that lets an ANALYST_READ-running Cortex
-- Agent tool call write an AUDIT_LOG row without ANALYST_READ ever being
-- granted INSERT on AUDIT_LOG directly. See sql/procedures/README.md for why
-- this exists instead of a direct grant.
--
-- HUMAN_DECISION/SIGNOFF_BY/SIGNOFF_AT are never set here — those belong to
-- an actual officer sign-off action (sql/rbac/04_officer_signoff.sql), never
-- to the call that produced the answer being signed off on. IS_EVAL is
-- always FALSE here; eval runs get their own separate write path per
-- architecture.md's Evaluation architecture, once that exists.

USE ROLE SECURITYADMIN;
USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE PROCEDURE SP_WRITE_AUDIT_LOG(
  RUN_ID VARCHAR, APP_USER VARCHAR, STAGE VARCHAR,
  PROMPT_OR_QUESTION VARCHAR, MODEL_VERSION VARCHAR,
  RETRIEVED_RULE_CHUNK_IDS ARRAY, QUERY_SNAPSHOT_ID VARCHAR,
  OUTPUT VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT INTO PRAMAN.CORE.AUDIT_LOG
    (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION,
     RETRIEVED_RULE_CHUNK_IDS, QUERY_SNAPSHOT_ID, OUTPUT, HUMAN_DECISION, IS_EVAL)
  VALUES
    (:RUN_ID, :APP_USER, :STAGE, :PROMPT_OR_QUESTION, :MODEL_VERSION,
     :RETRIEVED_RULE_CHUNK_IDS, :QUERY_SNAPSHOT_ID, :OUTPUT, NULL, FALSE);
  RETURN 'OK';
END;
$$;

-- AUDIT_INSERT can't CREATE PROCEDURE (sql/rbac/03_audit_insert.sql grants it
-- nothing but INSERT on AUDIT_LOG + USAGE on DB/schema), so the procedure is
-- created under SECURITYADMIN above and ownership transferred here. From
-- this point on, it runs with AUDIT_INSERT's privileges (EXECUTE AS OWNER),
-- regardless of which role calls it.
GRANT OWNERSHIP ON PROCEDURE SP_WRITE_AUDIT_LOG(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,ARRAY,VARCHAR,VARCHAR)
  TO ROLE AUDIT_INSERT COPY CURRENT GRANTS;

GRANT USAGE ON PROCEDURE SP_WRITE_AUDIT_LOG(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,ARRAY,VARCHAR,VARCHAR)
  TO ROLE ANALYST_READ;
