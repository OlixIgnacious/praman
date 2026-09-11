-- AUDIT_LOG — append-only by grant, not just by convention. No role,
-- including ACCOUNTADMIN in day-to-day use, gets UPDATE/DELETE on this
-- table (see sql/rbac/) — that's what makes "audit-ready" an enforced
-- property instead of a policy statement. IS_EVAL separates eval runs
-- from real usage so eval traffic never contaminates what an officer reviews.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS AUDIT_LOG (
  RUN_ID                  VARCHAR(64)       NOT NULL,
  RUN_TIMESTAMP            TIMESTAMP_NTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  APP_USER                 VARCHAR(128)      NOT NULL,
  STAGE                    VARCHAR(8)        NOT NULL,   -- '0' | '1' | '2' | '3'
  PROMPT_OR_QUESTION       VARCHAR(16777216),
  MODEL_VERSION            VARCHAR(128),
  RETRIEVED_RULE_CHUNK_IDS ARRAY,                         -- populated for Stage 1/2/3
  QUERY_SNAPSHOT_ID        VARCHAR(64),                   -- populated for Stage 0
  OUTPUT                   VARCHAR(16777216),
  HUMAN_DECISION           VARCHAR(32),                   -- e.g. 'accepted' | 'escalated' | 'rejected'
  SIGNOFF_BY               VARCHAR(128),
  SIGNOFF_AT               TIMESTAMP_NTZ,
  IS_EVAL                  BOOLEAN           NOT NULL DEFAULT FALSE,
  CONSTRAINT PK_AUDIT_LOG PRIMARY KEY (RUN_ID),
  CONSTRAINT CHK_AUDIT_LOG_STAGE CHECK (STAGE IN ('0', '1', '2', '3'))
)
COMMENT = 'Append-only run log — every Skill invocation. Insert-only grant enforced in sql/rbac/.';
