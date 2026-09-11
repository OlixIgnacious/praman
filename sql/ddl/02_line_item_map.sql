-- LINE_ITEM_MAP — the governed mapping from a report line item to where it
-- lives in our own schema. Stage 1 proposes rows (STATUS='proposed');
-- only a human governance approval flips a row to 'approved'. This table,
-- not Snowflake's own lineage graph, is what Stage 3 walks explicitly.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS LINE_ITEM_MAP (
  LINE_ITEM_ID     VARCHAR(64)   NOT NULL,   -- report line item code (DPM/MDRM-equivalent; RBI has no public
                                              -- machine-readable code list, so this is assigned internally)
  REPORT_NAME      VARCHAR(200)  NOT NULL,   -- e.g. 'Basel III Pillar 3 Disclosure'
  TAXONOMY_VERSION VARCHAR(32),
  DESCRIPTION      VARCHAR(1000),
  SOURCE_TABLE     VARCHAR(128)  NOT NULL,   -- e.g. 'GL_ENTRIES'
  SOURCE_COLUMN    VARCHAR(128)  NOT NULL,
  TRANSFORM_LOGIC  VARCHAR(4000),            -- SQL expression or plain-language rule
  RULE_CHUNK_ID    VARCHAR(64),              -- FK -> RULE_CORPUS.CHUNK_ID, the paragraph that mandates this field
  STATUS           VARCHAR(16)   NOT NULL DEFAULT 'proposed', -- 'proposed' | 'approved'
  APPROVED_BY      VARCHAR(128),
  APPROVED_AT      TIMESTAMP_NTZ,
  VALID_FROM       DATE          NOT NULL,
  VALID_TO         DATE,
  CONSTRAINT PK_LINE_ITEM_MAP PRIMARY KEY (LINE_ITEM_ID),
  CONSTRAINT FK_LINE_ITEM_MAP_RULE FOREIGN KEY (RULE_CHUNK_ID) REFERENCES RULE_CORPUS (CHUNK_ID),
  CONSTRAINT CHK_LINE_ITEM_MAP_STATUS CHECK (STATUS IN ('proposed', 'approved'))
)
COMMENT = 'Report line item -> source table/column mapping, human-approved. Read by all four stages.';
