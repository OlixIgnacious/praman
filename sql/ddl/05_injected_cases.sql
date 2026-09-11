-- INJECTED_CASES — the eval "answer key". Lives in EVAL, not CORE, on purpose:
-- see architecture.md, "Shared data model" — must never be reachable by a
-- Skill's runtime role, so a bug can't let the agent see what it's being
-- scored against. GL_ENTRIES/TRANSACTIONS reference this table's key, but
-- the FK is declared here in EVAL, not enforced cross-schema by Snowflake —
-- the isolation is enforced by grants (sql/rbac/), not by this constraint.

USE DATABASE PRAMAN;
USE SCHEMA EVAL;

CREATE TABLE IF NOT EXISTS INJECTED_CASES (
  CASE_ID            VARCHAR(64)   NOT NULL,
  TYPE               VARCHAR(32)   NOT NULL,  -- classification | timing | sign | unit_scale | double_counting
                                               -- | stale_ref | defensible_interpretation | correct_but_anomalous
                                               -- | structuring
  GROUND_TRUTH_LABEL VARCHAR(4000) NOT NULL,
  EXPECTED_STAGE     VARCHAR(8)    NOT NULL,  -- '0' | '2'
  DESCRIPTION        VARCHAR(1000),
  CREATED_AT         TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT PK_INJECTED_CASES PRIMARY KEY (CASE_ID),
  CONSTRAINT CHK_INJECTED_CASES_TYPE CHECK (
    TYPE IN ('classification', 'timing', 'sign', 'unit_scale', 'double_counting',
             'stale_ref', 'defensible_interpretation', 'correct_but_anomalous', 'structuring')
  ),
  CONSTRAINT CHK_INJECTED_CASES_STAGE CHECK (EXPECTED_STAGE IN ('0', '2'))
)
COMMENT = 'Named error/signal catalogue for eval only — never surfaced to a Skill at runtime';
