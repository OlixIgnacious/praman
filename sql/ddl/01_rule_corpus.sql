-- RULE_CORPUS — base table Cortex Search indexes. One row per chunk of a
-- parsed circular/Master Direction (PARSE_DOCUMENT output), not per document.
-- SECTION_REF/PAGE_NO carried through chunking manually so citations can
-- point at a paragraph, not just a document.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS RULE_CORPUS (
  CHUNK_ID            VARCHAR(64)     NOT NULL,
  DOC_ID               VARCHAR(64)     NOT NULL,   -- e.g. 'RBI/DoS/2026-27/415'
  DOC_TITLE            VARCHAR(500),
  JURISDICTION         VARCHAR(16)     NOT NULL,    -- e.g. 'IN'
  VERSION              VARCHAR(32)     NOT NULL,
  EFFECTIVE_DATE       DATE,
  SECTION_REF          VARCHAR(128),
  PAGE_NO               NUMBER(6,0),
  CHUNK_TEXT           VARCHAR(16777216) NOT NULL,
  SUPERSEDES_CHUNK_ID  VARCHAR(64),
  SOURCE_FILE          VARCHAR(500),               -- path under data/raw/circulars/
  INGESTED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT PK_RULE_CORPUS PRIMARY KEY (CHUNK_ID),
  CONSTRAINT FK_RULE_CORPUS_SUPERSEDES FOREIGN KEY (SUPERSEDES_CHUNK_ID) REFERENCES RULE_CORPUS (CHUNK_ID)
)
COMMENT = 'Chunked, versioned circular/Master Direction text — indexed by Cortex Search for Stage 1/2/3 citation';
