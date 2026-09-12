-- LINE_ITEM_MAP_SV — the Stage 2 governance gate as a queryable Semantic
-- View. Added after a real bug: SIGNAL_ASSURE_AGENT originally had no tool
-- to query LINE_ITEM_MAP at all, so its "no approved mapping" answers were
-- a hardcoded default, not an actual STATUS check (see plan.md, Days 12–15).
-- The agent's line_item_map_lookup tool queries this view as the mandatory
-- first step of every Stage 2 flow — check STATUS before computing anything.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE SEMANTIC VIEW LINE_ITEM_MAP_SV

  TABLES (
    LINE_ITEM_MAP PRIMARY KEY (LINE_ITEM_ID)
  )

  DIMENSIONS (
    LINE_ITEM_MAP.LINE_ITEM_ID    AS LINE_ITEM_ID
      WITH SYNONYMS ('line item', 'line item ID', 'Pillar 3 line item'),
    LINE_ITEM_MAP.REPORT_NAME     AS REPORT_NAME
      WITH SYNONYMS ('report', 'return name'),
    LINE_ITEM_MAP.DESCRIPTION     AS DESCRIPTION
      WITH SYNONYMS ('line item description'),
    LINE_ITEM_MAP.SOURCE_TABLE    AS SOURCE_TABLE
      WITH SYNONYMS ('source table'),
    LINE_ITEM_MAP.SOURCE_COLUMN   AS SOURCE_COLUMN
      WITH SYNONYMS ('source column'),
    LINE_ITEM_MAP.TRANSFORM_LOGIC AS TRANSFORM_LOGIC
      WITH SYNONYMS ('aggregation logic', 'computation', 'formula'),
    LINE_ITEM_MAP.RULE_CHUNK_ID   AS RULE_CHUNK_ID
      WITH SYNONYMS ('rule reference', 'regulatory citation', 'backing rule'),
    LINE_ITEM_MAP.STATUS          AS STATUS
      WITH SYNONYMS ('approval status', 'governance status', 'mapping status'),
    LINE_ITEM_MAP.APPROVED_BY     AS APPROVED_BY
      WITH SYNONYMS ('approver'),
    LINE_ITEM_MAP.APPROVED_AT     AS APPROVED_AT
      WITH SYNONYMS ('approval date'),
    LINE_ITEM_MAP.VALID_FROM      AS VALID_FROM,
    LINE_ITEM_MAP.VALID_TO        AS VALID_TO
  )

  METRICS (
    LINE_ITEM_MAP.MAPPING_COUNT AS COUNT(LINE_ITEM_ID)
      WITH SYNONYMS ('number of mappings', 'line item count')
  )

  COMMENT = 'Governance-controlled report line item to source mapping. Stage 2 must check STATUS=approved here before computing any line item value.'

  AI_SQL_GENERATION 'Use this view to check LINE_ITEM_MAP.STATUS for a given LINE_ITEM_ID before computing any value in Stage 2. Filter by STATUS = ''approved'' to find approved mappings. RULE_CHUNK_ID links to RULE_CORPUS for the regulatory citation backing each mapping. TRANSFORM_LOGIC describes how to compute the line item value from the source table/column.';

GRANT SELECT ON SEMANTIC VIEW LINE_ITEM_MAP_SV TO ROLE ANALYST_READ;
