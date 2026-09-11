-- EVAL_RESULTS — scoring table. An eval run calls the same Skill production
-- traffic uses, against a held-out case, with AUDIT_LOG.IS_EVAL=TRUE; this
-- table is where that run gets compared against ground truth. 'abstained'
-- is a first-class MATCH_STATUS, not a missing row — see architecture.md,
-- "Evaluation architecture", on why that matters for the coverage argument.

USE DATABASE PRAMAN;
USE SCHEMA EVAL;

CREATE TABLE IF NOT EXISTS EVAL_RESULTS (
  EVAL_ID            VARCHAR(64)   NOT NULL,
  RUN_ID              VARCHAR(64)   NOT NULL,   -- FK -> PRAMAN.CORE.AUDIT_LOG.RUN_ID, not enforced cross-schema
  STAGE               VARCHAR(8)    NOT NULL,
  CASE_ID             VARCHAR(64),              -- FK -> INJECTED_CASES, when the case is synthetic
  DISCLOSURE_ID       VARCHAR(64),              -- FK -> PRAMAN.CORE.DIVERGENCE_DISCLOSURES, when ground truth is a real disclosure
  TAXONOMY_DELTA_ID   VARCHAR(64),              -- Stage 1 ground truth, not yet a standalone table (small enough to inline for the prototype)
  ERROR_TYPE          VARCHAR(32)   NOT NULL,
  GROUND_TRUTH_LABEL  VARCHAR(4000) NOT NULL,
  AGENT_OUTPUT        VARCHAR(16777216),
  MATCH_STATUS        VARCHAR(16)   NOT NULL,   -- 'true_positive' | 'false_positive' | 'false_negative' | 'abstained'
  MODEL_VERSION       VARCHAR(128),
  RULE_VERSION        VARCHAR(32),
  SCORED_AT           TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT PK_EVAL_RESULTS PRIMARY KEY (EVAL_ID),
  CONSTRAINT FK_EVAL_RESULTS_CASE FOREIGN KEY (CASE_ID) REFERENCES INJECTED_CASES (CASE_ID),
  CONSTRAINT CHK_EVAL_RESULTS_MATCH CHECK (
    MATCH_STATUS IN ('true_positive', 'false_positive', 'false_negative', 'abstained')
  )
)
COMMENT = 'Eval scoring — precision/recall per ERROR_TYPE via GROUP BY, never aggregate.';
