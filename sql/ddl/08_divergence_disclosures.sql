-- DIVERGENCE_DISCLOSURES — India-specific ground truth #1 for Stage 2 eval,
-- replacing the FILED_RETURNS/AMENDED_RETURNS pair the data model originally
-- assumed (that design predated the jurisdiction pick and RBI's CIMS gate —
-- see architecture.md). Populated from data/raw/divergence/: a bank's own
-- reported NPA/provisioning vs. RBI's post-inspection assessment, disclosed
-- publicly when the gap exceeds a regulatory threshold.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS DIVERGENCE_DISCLOSURES (
  DISCLOSURE_ID      VARCHAR(64)   NOT NULL,
  BANK_NAME          VARCHAR(200)  NOT NULL,   -- real bank, e.g. 'YES Bank' — ground truth, not synthetic
  FISCAL_YEAR        VARCHAR(8)    NOT NULL,   -- e.g. 'FY19'
  LINE_ITEM_ID       VARCHAR(64)   NOT NULL,   -- FK -> LINE_ITEM_MAP, e.g. Gross NPA, Provisioning
  REPORTED_VALUE     NUMBER(20,2)  NOT NULL,   -- what the bank originally disclosed
  RBI_ASSESSED_VALUE NUMBER(20,2)  NOT NULL,   -- what RBI's inspection found
  DIVERGENCE_AMOUNT  NUMBER(20,2)  NOT NULL,
  DIVERGENCE_PCT     NUMBER(9,4),              -- the threshold-triggering percentage
  DISCLOSURE_DATE    DATE,
  SOURCE_DOCUMENT    VARCHAR(500)  NOT NULL,   -- path under data/raw/divergence/
  CONSTRAINT PK_DIVERGENCE_DISCLOSURES PRIMARY KEY (DISCLOSURE_ID),
  CONSTRAINT FK_DIVERGENCE_DISCLOSURES_LINE_ITEM FOREIGN KEY (LINE_ITEM_ID) REFERENCES LINE_ITEM_MAP (LINE_ITEM_ID)
)
COMMENT = 'Real "bank reported vs. RBI-corrected" pairs — India substitute for literal amended-vs-original filings. Stage 2 eval ground truth #1.';
