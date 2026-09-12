-- TRANSACTIONS_SV — Stage 0's live signal surface over the transaction feed.
-- Forked from semantic-view-patterns' entity_facts (counterparty as the
-- shared dimension) and window_metrics (trailing-window aggregates) patterns.
--
-- Transactions are event-level facts, not snapshots — every metric here is
-- fully additive across every dimension, unlike POSITIONS_SV's NOTIONAL.
--
-- The trailing-window metrics are raw building blocks for "which
-- counterparties look like structuring" (architecture.md, Stage 0), not the
-- detector itself: the actual threshold/scoring logic is the deterministic
-- detector (sql/ddl item 12 in plan.md), shared with Stage 2. This view only
-- exposes the aggregates a detector — or an analyst asking a follow-up
-- question — would need without re-deriving them by hand.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE SEMANTIC VIEW TRANSACTIONS_SV

  TABLES (
    transactions   AS TRANSACTIONS   PRIMARY KEY (TXN_ID),
    counterparties AS COUNTERPARTIES PRIMARY KEY (COUNTERPARTY_ID)
  )

  RELATIONSHIPS (
    txn_to_counterparty AS transactions(COUNTERPARTY_ID) REFERENCES counterparties
  )

  DIMENSIONS (
    counterparties.name                AS NAME
      WITH SYNONYMS ('counterparty name', 'client name'),
    counterparties.sector              AS SECTOR
      WITH SYNONYMS ('industry', 'sector'),
    counterparties.jurisdiction        AS JURISDICTION
      WITH SYNONYMS ('jurisdiction', 'country', 'domestic or overseas'),
    counterparties.risk_rating         AS RISK_RATING
      WITH SYNONYMS ('credit rating', 'risk rating'),
    counterparties.concentration_group AS CONCENTRATION_GROUP
      WITH SYNONYMS ('concentration group', 'large exposure group'),

    transactions.channel  AS CHANNEL
      WITH SYNONYMS ('payment channel', 'channel', 'payment rail'),
    transactions.txn_date AS TO_DATE(TXN_TIMESTAMP)
      WITH SYNONYMS ('date', 'transaction date', 'day'),
    transactions.txn_hour AS HOUR(TXN_TIMESTAMP)
      WITH SYNONYMS ('hour of day', 'time of day')
  )

  METRICS (
    transactions.total_amount AS SUM(AMOUNT)
      WITH SYNONYMS ('total transaction amount', 'transaction volume', 'total value transacted'),
    transactions.txn_count AS COUNT(TXN_ID)
      WITH SYNONYMS ('number of transactions', 'transaction count'),
    transactions.avg_txn_amount AS AVG(AMOUNT)
      WITH SYNONYMS ('average transaction size', 'average transaction amount'),

    -- Rolling 7-day building blocks — PARTITION BY EXCLUDING txn_date means
    -- "partition by whatever else the query groups by" (e.g. counterparty,
    -- channel), so these stay meaningful whether sliced by counterparty,
    -- sector, or channel.
    transactions.total_amount_trailing_7d AS
      SUM(total_amount)
      OVER (PARTITION BY EXCLUDING transactions.txn_date
            ORDER BY transactions.txn_date
            RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW)
      WITH SYNONYMS ('trailing 7-day transaction volume', 'weekly transaction volume')
      COMMENT = 'Rolling 7-day sum, requires transactions.txn_date (or a coarser date grain) as a query dimension to be meaningful.',

    transactions.txn_count_trailing_7d AS
      SUM(txn_count)
      OVER (PARTITION BY EXCLUDING transactions.txn_date
            ORDER BY transactions.txn_date
            RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW)
      WITH SYNONYMS ('trailing 7-day transaction count', 'weekly transaction frequency')
      COMMENT = 'Rolling 7-day count, requires transactions.txn_date (or a coarser date grain) as a query dimension to be meaningful.'
  )

  COMMENT = 'Transaction-level feed for Stage 0 live signal queries. All metrics fully additive across every dimension (event-level facts, not snapshots) — contrast with POSITIONS_SV.total_notional, which is semi-additive.'

  AI_SQL_GENERATION 'Use total_amount/txn_count for plain volume questions. Use total_amount_trailing_7d/txn_count_trailing_7d ONLY alongside transactions.txn_date (or a coarser date dimension) in the query — they are rolling windows and are meaningless without a date axis. Group by counterparties.sector or counterparties.concentration_group to check sector/large-exposure concentration in transaction activity. These trailing metrics surface raw structuring/velocity signal inputs; they are not a fraud verdict on their own — pair with counterparties.risk_rating and channel for context before treating a spike as a flag.';

GRANT USAGE ON SEMANTIC VIEW TRANSACTIONS_SV TO ROLE ANALYST_READ;
