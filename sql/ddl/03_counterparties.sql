-- COUNTERPARTIES — the synthetic firm's counterparty book. No dependencies;
-- generated first by the synthetic data generator.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE TABLE IF NOT EXISTS COUNTERPARTIES (
  COUNTERPARTY_ID     VARCHAR(64)   NOT NULL,
  NAME                VARCHAR(200)  NOT NULL,   -- synthetic, not a real counterparty
  SECTOR              VARCHAR(100),
  JURISDICTION        VARCHAR(16),
  RISK_RATING         VARCHAR(8),
  CONCENTRATION_GROUP VARCHAR(100),             -- groups counterparties that share a concentration limit
  CREATED_AT          TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT PK_COUNTERPARTIES PRIMARY KEY (COUNTERPARTY_ID)
)
COMMENT = 'Synthetic counterparty book, read by Stage 0 (Semantic View) and Stage 3';
