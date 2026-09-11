-- TRANSACTIONS — transaction-level detail feeding Stage 0's live signal
-- queries and the deterministic outlier/structuring detectors.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS TRANSACTIONS (
  TXN_ID            VARCHAR(64)     NOT NULL,
  COUNTERPARTY_ID   VARCHAR(64)     NOT NULL,
  AMOUNT            NUMBER(20,2)    NOT NULL,
  CURRENCY          VARCHAR(8)      NOT NULL DEFAULT 'INR',
  TXN_TIMESTAMP     TIMESTAMP_NTZ   NOT NULL,
  CHANNEL           VARCHAR(64),                -- e.g. 'RTGS', 'NEFT', 'branch cash'
  INJECTED_CASE_ID  VARCHAR(64),                -- FK -> PRAMAN.EVAL.INJECTED_CASES.CASE_ID, not enforced cross-schema
  CONSTRAINT PK_TRANSACTIONS PRIMARY KEY (TXN_ID),
  CONSTRAINT FK_TRANSACTIONS_COUNTERPARTY FOREIGN KEY (COUNTERPARTY_ID) REFERENCES COUNTERPARTIES (COUNTERPARTY_ID)
)
COMMENT = 'Synthetic transaction feed. Read by Stage 0 (Semantic View + deterministic detectors)';
