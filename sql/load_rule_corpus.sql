-- Load ingest/chunk_circular.py's output into PRAMAN.CORE.RULE_CORPUS.
-- Column order in data/processed/rule_corpus_chunks.csv matches an explicit
-- column list here (not pure positional) because RULE_CORPUS.INGESTED_AT
-- has a DEFAULT and isn't in the CSV at all.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE FILE FORMAT IF NOT EXISTS CSV_FORMAT
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('');

CREATE OR REPLACE TEMPORARY STAGE RULE_CORPUS_STAGE FILE_FORMAT = CSV_FORMAT;

PUT 'file:///Users/olixstudios/Documents/workspace/Projects/hackathons/snowflake/data/processed/rule_corpus_chunks.csv' @RULE_CORPUS_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;

COPY INTO RULE_CORPUS (CHUNK_ID, DOC_ID, DOC_TITLE, JURISDICTION, VERSION, EFFECTIVE_DATE, SECTION_REF, PAGE_NO, CHUNK_TEXT, SUPERSEDES_CHUNK_ID, SOURCE_FILE)
FROM @RULE_CORPUS_STAGE/rule_corpus_chunks.csv.gz
FILE_FORMAT = (FORMAT_NAME = CSV_FORMAT)
ON_ERROR = ABORT_STATEMENT;
