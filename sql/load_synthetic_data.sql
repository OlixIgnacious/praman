-- Load of generator/generate_synthetic_data.py's output into PRAMAN.CORE.
-- Column order in data/synthetic/*.csv matches each table's DDL column order
-- exactly (verified against sql/ddl/03-07), so positional COPY INTO is safe here.
--
-- TRUNCATE before each COPY INTO, deliberately -- this script is meant to be
-- re-run whenever data/synthetic/*.csv regenerates (e.g. after
-- inject_eval_cases() added rows for the eval catalogue), and COPY INTO has
-- no upsert/diff semantics: if the file's content changed since the last
-- load, Snowflake treats it as a new file and inserts every row in it again,
-- rather than only the new ones -- silently duplicating the whole table.
-- TRUNCATE + reload is the correct idempotent pattern here, not FORCE=TRUE.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('');

CREATE OR REPLACE TEMPORARY STAGE SYNTHETIC_STAGE FILE_FORMAT = CSV_FORMAT;

PUT 'file:///Users/olixstudios/Documents/workspace/Projects/hackathons/snowflake/data/synthetic/counterparties.csv' @SYNTHETIC_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
PUT 'file:///Users/olixstudios/Documents/workspace/Projects/hackathons/snowflake/data/synthetic/positions.csv' @SYNTHETIC_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
PUT 'file:///Users/olixstudios/Documents/workspace/Projects/hackathons/snowflake/data/synthetic/gl_entries.csv' @SYNTHETIC_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
PUT 'file:///Users/olixstudios/Documents/workspace/Projects/hackathons/snowflake/data/synthetic/transactions.csv' @SYNTHETIC_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;

-- Reverse dependency order (children before parents) -- doesn't matter for
-- Snowflake's own enforcement (FKs aren't enforced at write time, per
-- sql/ddl/README.md), but keeps this readable as "undo the load" order.
TRUNCATE TABLE TRANSACTIONS;
TRUNCATE TABLE GL_ENTRIES;
TRUNCATE TABLE POSITIONS;
TRUNCATE TABLE COUNTERPARTIES;

COPY INTO COUNTERPARTIES FROM @SYNTHETIC_STAGE/counterparties.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO POSITIONS FROM @SYNTHETIC_STAGE/positions.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO GL_ENTRIES FROM @SYNTHETIC_STAGE/gl_entries.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO TRANSACTIONS FROM @SYNTHETIC_STAGE/transactions.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
