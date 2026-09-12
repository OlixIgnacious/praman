-- AUDIT_EVIDENCE_PACK — the compliance-facing view of AUDIT_LOG, per
-- architecture.md's Evaluation architecture ("Compliance, internal audit,
-- evidence pack export"). One row per real invocation, IS_EVAL=TRUE
-- excluded (eval traffic never contaminates what an officer/examiner
-- reviews — the exact point architecture.md's Evaluation architecture makes
-- about IS_EVAL), citations resolved from RETRIEVED_RULE_CHUNK_IDS against
-- RULE_CORPUS so a reviewer sees the actual cited paragraph text, not a bare
-- chunk ID.
--
-- Mechanism: this project has no scheduled-task/pipeline infrastructure
-- anywhere else (every SQL change here runs by hand, in an interactive
-- cortex session — see NOTES.md's standing convention), so this is a plain
-- view, not an automated unload. A reviewer runs a SELECT against it and
-- downloads the result as CSV from Snowsight or the cortex CLI. A COPY INTO
-- @stage unload would be the next step if this needs to leave Snowflake as
-- a file on a schedule, but nothing in this project's current scope needs
-- that yet — building it now would be automation with no pipeline to hang
-- it on.
--
-- KNOWN GAP, not fixed here (out of scope for this file, flagged for a
-- human decision): sql/rbac/04_officer_signoff.sql's own header comment
-- describes a sign-off as "a new row... RUN_ID referencing the run being
-- signed off on" — but RUN_ID is AUDIT_LOG's primary key, so a sign-off row
-- cannot both have its own unique RUN_ID and store the original run's
-- RUN_ID in that same column. There is no separate linking column (e.g. a
-- SIGNOFF_FOR_RUN_ID) today, and no procedure yet writes a sign-off row at
-- all (only SP_WRITE_AUDIT_LOG exists, owned by AUDIT_INSERT, and it always
-- leaves HUMAN_DECISION/SIGNOFF_BY/SIGNOFF_AT NULL). This view surfaces
-- those three columns as-is; today, every real row has them NULL. Don't
-- read a populated-looking sign-off join into this view — there isn't one
-- yet to join against.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE VIEW AUDIT_EVIDENCE_PACK AS
WITH cited AS (
  SELECT
    a.RUN_ID,
    ARRAY_AGG(
      OBJECT_CONSTRUCT(
        'CHUNK_ID', rc.CHUNK_ID,
        'DOC_TITLE', rc.DOC_TITLE,
        'SECTION_REF', rc.SECTION_REF,
        'CHUNK_TEXT', rc.CHUNK_TEXT
      )
    ) WITHIN GROUP (ORDER BY rc.CHUNK_ID) AS CITATIONS
  FROM AUDIT_LOG a,
       LATERAL FLATTEN(INPUT => a.RETRIEVED_RULE_CHUNK_IDS) f
  JOIN RULE_CORPUS rc ON rc.CHUNK_ID = f.VALUE::VARCHAR
  WHERE a.IS_EVAL = FALSE
  GROUP BY a.RUN_ID
)
SELECT
  a.RUN_ID,
  a.RUN_TIMESTAMP,
  a.APP_USER,
  a.STAGE,
  a.PROMPT_OR_QUESTION,
  a.MODEL_VERSION,
  a.QUERY_SNAPSHOT_ID,
  a.OUTPUT,
  a.HUMAN_DECISION,
  a.SIGNOFF_BY,
  a.SIGNOFF_AT,
  COALESCE(c.CITATIONS, ARRAY_CONSTRUCT()) AS CITATIONS
FROM AUDIT_LOG a
LEFT JOIN cited c ON c.RUN_ID = a.RUN_ID
WHERE a.IS_EVAL = FALSE
ORDER BY a.STAGE, a.RUN_TIMESTAMP;

-- No role can currently read AUDIT_LOG at all (ANALYST_READ/GOVERNANCE_WRITE
-- were never granted SELECT on it; AUDIT_INSERT/OFFICER_SIGNOFF are
-- deliberately insert-only by their own design intent — see their header
-- comments in sql/rbac/ — so granting either of them read access here would
-- undo the one property that makes "insert-only" an enforced boundary
-- rather than a policy statement). Of the four existing roles,
-- GOVERNANCE_WRITE is the closest fit: it's already this project's other
-- control/oversight role (approves LINE_ITEM_MAP, reviews RULE_CORPUS
-- before approving), not the day-to-day operational role ANALYST_READ is.
-- Flagging honestly: this is still an imperfect fit — no existing role is
-- actually "the compliance officer/examiner reviewing evidence," and a
-- dedicated role (e.g. AUDIT_REVIEW) would be the architecturally correct
-- long-term answer. Introducing a new role is a real RBAC decision, not
-- something to add unilaterally inside an export-view file — left for a
-- human call, not resolved here.
GRANT SELECT ON VIEW AUDIT_EVIDENCE_PACK TO ROLE GOVERNANCE_WRITE;
