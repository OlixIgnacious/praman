-- One-time load of generator/generate_synthetic_data.py's output into PRAMAN.CORE.
-- Column order in data/synthetic/*.csv matches each table's DDL column order
-- exactly (verified against sql/ddl/03-07), so positional COPY INTO is safe here.

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

COPY INTO COUNTERPARTIES FROM @SYNTHETIC_STAGE/counterparties.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO POSITIONS FROM @SYNTHETIC_STAGE/positions.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO GL_ENTRIES FROM @SYNTHETIC_STAGE/gl_entries.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
COPY INTO TRANSACTIONS FROM @SYNTHETIC_STAGE/transactions.csv.gz FILE_FORMAT=(FORMAT_NAME=CSV_FORMAT) ON_ERROR=ABORT_STATEMENT;
