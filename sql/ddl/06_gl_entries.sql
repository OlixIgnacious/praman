-- GL_ENTRIES — synthesized general ledger, generated bottom-up so it
-- aggregates to HDFC Bank's real disclosed Pillar 3 line items.
-- INJECTED_CASE_ID is nullable and points into EVAL.INJECTED_CASES —
-- most rows are clean; only the deliberately-broken ones carry a case ID.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS GL_ENTRIES (
  ENTRY_ID          VARCHAR(64)   NOT NULL,
  ACCOUNT_CODE      VARCHAR(64)   NOT NULL,
  AMOUNT            NUMBER(20,2)  NOT NULL,
  CURRENCY          VARCHAR(8)    NOT NULL DEFAULT 'INR',
  POSTING_DATE      DATE          NOT NULL,
  COUNTERPARTY_ID   VARCHAR(64),
  POSITION_ID       VARCHAR(64),
  INJECTED_CASE_ID  VARCHAR(64),  -- FK -> PRAMAN.EVAL.INJECTED_CASES.CASE_ID, not enforced cross-schema
  CONSTRAINT PK_GL_ENTRIES PRIMARY KEY (ENTRY_ID),
  CONSTRAINT FK_GL_ENTRIES_COUNTERPARTY FOREIGN KEY (COUNTERPARTY_ID) REFERENCES COUNTERPARTIES (COUNTERPARTY_ID),
  CONSTRAINT FK_GL_ENTRIES_POSITION FOREIGN KEY (POSITION_ID) REFERENCES POSITIONS (POSITION_ID)
)
COMMENT = 'Synthetic general ledger, aggregates to real HDFC Bank Pillar 3 line items. Read by Stage 2, Stage 3 lineage trace.';
