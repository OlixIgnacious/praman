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
  SIGNOFF_FOR_RUN_ID       VARCHAR(64),                   -- NULL on a normal run row; set only on a sign-off row,
                                                           -- pointing at the RUN_ID being signed off on (see below)
  IS_EVAL                  BOOLEAN           NOT NULL DEFAULT FALSE,
  CONSTRAINT PK_AUDIT_LOG PRIMARY KEY (RUN_ID),
  CONSTRAINT CHK_AUDIT_LOG_STAGE CHECK (STAGE IN ('0', '1', '2', '3')),
  CONSTRAINT FK_AUDIT_LOG_SIGNOFF_FOR_RUN FOREIGN KEY (SIGNOFF_FOR_RUN_ID) REFERENCES AUDIT_LOG (RUN_ID)
)
COMMENT = 'Append-only run log — every Skill invocation. Insert-only grant enforced in sql/rbac/. A sign-off is recorded as a NEW row (HUMAN_DECISION/SIGNOFF_BY/SIGNOFF_AT populated, SIGNOFF_FOR_RUN_ID pointing at the original run), never an UPDATE of the run being signed off on — see sql/procedures/02_sp_record_signoff.sql.';

-- Real gap found and fixed, not part of the original design: sql/rbac/
-- 04_officer_signoff.sql's own header comment always described a sign-off
-- row as "referencing the run being signed off on," but RUN_ID is this
-- table's own primary key, so a sign-off row could not both have its own
-- unique RUN_ID and store the original run's RUN_ID in that same column.
-- SIGNOFF_FOR_RUN_ID is the actual linking column that comment assumed
-- existed. ALTER, not just the CREATE above, since this account's AUDIT_LOG
-- already existed (Days 3-6) before this fix landed -- CREATE TABLE IF NOT
-- EXISTS alone would be a no-op against it.
ALTER TABLE AUDIT_LOG ADD COLUMN IF NOT EXISTS SIGNOFF_FOR_RUN_ID VARCHAR(64);
