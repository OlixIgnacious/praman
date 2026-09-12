-- SP_WRITE_AUDIT_LOG — the bridge that lets an ANALYST_READ-running Cortex
-- Agent tool call write an AUDIT_LOG row without ANALYST_READ ever being
-- granted INSERT on AUDIT_LOG directly. See sql/procedures/README.md for why
-- this exists instead of a direct grant.
--
-- HUMAN_DECISION/SIGNOFF_BY/SIGNOFF_AT are never set here — those belong to
-- an actual officer sign-off action (sql/rbac/04_officer_signoff.sql), never
-- to the call that produced the answer being signed off on.
--
-- IS_EVAL: added as a 9th param (VARCHAR 'TRUE'/'FALSE', not BOOLEAN — same
-- reason RETRIEVED_RULE_CHUNK_IDS is VARCHAR not ARRAY: Cortex Agent generic
-- tools with warehouse execution don't handle non-string argument types
-- reliably). SIGNAL_ASSURE_AGENT's orchestration sets this from a "[EVAL]"
-- prompt marker (cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml) — an eval
-- run goes through the exact same agent/tool path as live traffic
-- (architecture.md's Evaluation architecture: "same path, held-out input"),
-- with only this flag differing, so eval questions never get miscounted as
-- real analyst usage in AUDIT_LOG. Required, not optional, in the tool's
-- input_schema — the agent drops arguments it treats as optional (see
-- plan.md's Days 9-12 entry), which silently breaks positional procedure
-- calls if any param is missing.

-- ACCOUNTADMIN, not SECURITYADMIN, for this one: the 8-arg SP_WRITE_AUDIT_LOG
-- already exists and is owned by AUDIT_INSERT (transferred there the first
-- time this file ran). SECURITYADMIN's MANAGE GRANTS privilege was enough to
-- make that original transfer, but DROP requires OWNERSHIP specifically --
-- don't assume SECURITYADMIN has a role-hierarchy path to an object AUDIT_INSERT
-- now owns. ACCOUNTADMIN unambiguously can drop/create/re-grant anything
-- account-wide, and it's this project's actual connected role anyway.
USE ROLE ACCOUNTADMIN;
USE DATABASE PRAMAN;
USE SCHEMA CORE;

-- Snowflake identifies a procedure by name + argument signature, so
-- CREATE OR REPLACE with a 9th argument does NOT replace the original
-- 8-argument procedure -- it creates a second overload alongside it,
-- leaving the stale 8-arg version (already owned by AUDIT_INSERT) lying
-- around. Drop it explicitly first.
DROP PROCEDURE IF EXISTS SP_WRITE_AUDIT_LOG(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR);

CREATE OR REPLACE PROCEDURE SP_WRITE_AUDIT_LOG(
  RUN_ID VARCHAR, APP_USER VARCHAR, STAGE VARCHAR,
  PROMPT_OR_QUESTION VARCHAR, MODEL_VERSION VARCHAR,
  RETRIEVED_RULE_CHUNK_IDS VARCHAR, QUERY_SNAPSHOT_ID VARCHAR,
  OUTPUT VARCHAR, IS_EVAL VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Accepts RETRIEVED_RULE_CHUNK_IDS as a comma-delimited VARCHAR (not ARRAY) and IS_EVAL as VARCHAR TRUE/FALSE (not BOOLEAN) because Cortex Agent generic tools with warehouse execution do not support those types reliably. Parsed to native types on insert.'
AS
$$
BEGIN
  INSERT INTO PRAMAN.CORE.AUDIT_LOG
    (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION,
     RETRIEVED_RULE_CHUNK_IDS, QUERY_SNAPSHOT_ID, OUTPUT, HUMAN_DECISION, IS_EVAL)
  SELECT :RUN_ID, :APP_USER, :STAGE, :PROMPT_OR_QUESTION, :MODEL_VERSION,
         IFF(:RETRIEVED_RULE_CHUNK_IDS = '' OR :RETRIEVED_RULE_CHUNK_IDS IS NULL,
             ARRAY_CONSTRUCT(),
             SPLIT(:RETRIEVED_RULE_CHUNK_IDS, ',')),
         :QUERY_SNAPSHOT_ID, :OUTPUT, NULL,
         IFF(UPPER(:IS_EVAL) = 'TRUE', TRUE, FALSE);
  RETURN 'OK';
END;
$$;

-- AUDIT_INSERT can't CREATE PROCEDURE (sql/rbac/03_audit_insert.sql grants it
-- nothing but INSERT on AUDIT_LOG + USAGE on DB/schema), so the procedure is
-- created under an admin role above and ownership transferred here. From
-- this point on, it runs with AUDIT_INSERT's privileges (EXECUTE AS OWNER),
-- regardless of which role calls it.
GRANT OWNERSHIP ON PROCEDURE SP_WRITE_AUDIT_LOG(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR)
  TO ROLE AUDIT_INSERT COPY CURRENT GRANTS;

GRANT USAGE ON PROCEDURE SP_WRITE_AUDIT_LOG(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR)
  TO ROLE ANALYST_READ;
