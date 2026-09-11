-- POSITIONS — balance sheet / off-balance-sheet exposures, synthesized
-- bottom-up from HDFC Bank's Basel III Pillar 3 disclosure (data/raw/pillar3/).

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS POSITIONS (
  POSITION_ID     VARCHAR(64)     NOT NULL,
  INSTRUMENT_TYPE VARCHAR(100)    NOT NULL,   -- e.g. 'Interest rate derivative', 'Term loan'
  NOTIONAL        NUMBER(20,2)    NOT NULL,
  CURRENCY        VARCHAR(8)      NOT NULL DEFAULT 'INR',
  EXPOSURE_CLASS  VARCHAR(100),               -- Basel exposure class, for capital-adequacy line items
  COUNTERPARTY_ID VARCHAR(64)     NOT NULL,
  AS_OF_DATE      DATE            NOT NULL,
  CONSTRAINT PK_POSITIONS PRIMARY KEY (POSITION_ID),
  CONSTRAINT FK_POSITIONS_COUNTERPARTY FOREIGN KEY (COUNTERPARTY_ID) REFERENCES COUNTERPARTIES (COUNTERPARTY_ID)
)
COMMENT = 'Synthetic position book, read by Stage 0 (Semantic View) and Stage 3';
