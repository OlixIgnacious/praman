-- Cortex Search Service over RULE_CORPUS — the managed chunk+embed+index step
-- that turns the rows sql/load_rule_corpus.sql loaded into something Stage 1/2/3
-- can query and cite. Per architecture.md's platform notes, Cortex Search does
-- NOT parse PDFs itself; that already happened upstream (ingest/chunk_circular.py,
-- against the pre-scraped text in data/raw/circulars/) — this step only
-- indexes CHUNK_TEXT, which is already at the right paragraph grain.
--
-- Uses the account's default warehouse, COMPUTE_WH (confirmed via
-- SHOW WAREHOUSES; — the only other two are SNOWFLAKE_LEARNING_WH and
-- SYSTEM$STREAMLIT_NOTEBOOK_WH, both Snowflake-provisioned, not ours).

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE CORTEX SEARCH SERVICE RULE_CORPUS_SEARCH
  ON CHUNK_TEXT
  ATTRIBUTES CHUNK_ID, DOC_ID, JURISDICTION, VERSION, SECTION_REF, EFFECTIVE_DATE
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 day'
  AS (
    SELECT CHUNK_ID, DOC_ID, DOC_TITLE, JURISDICTION, VERSION, EFFECTIVE_DATE,
           SECTION_REF, PAGE_NO, CHUNK_TEXT, SOURCE_FILE
    FROM RULE_CORPUS
  );

GRANT USAGE ON CORTEX SEARCH SERVICE RULE_CORPUS_SEARCH TO ROLE ANALYST_READ;

-- Sanity check once created:
-- SELECT PARSE_JSON(
--   SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
--     'PRAMAN.CORE.RULE_CORPUS_SEARCH',
--     '{"query": "timeline for submitting supervisory returns", "limit": 3}'
--   )
-- );
