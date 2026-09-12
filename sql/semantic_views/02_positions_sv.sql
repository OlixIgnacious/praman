-- POSITIONS_SV — balance-sheet exposure snapshot for Stage 0/3.
-- Forked from semantic-view-patterns' semi_additive_metric pattern:
-- POSITIONS.NOTIONAL is a point-in-time balance, not a transaction — summing
-- it across dates would double-count in a way summing across counterparties
-- does not. NON ADDITIVE BY guards that even though the synthetic book
-- currently has only one AS_OF_DATE, so the guard costs nothing today and
-- protects correctness the moment a second snapshot date is loaded.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE SEMANTIC VIEW POSITIONS_SV

  TABLES (
    positions      AS POSITIONS      PRIMARY KEY (POSITION_ID),
    counterparties AS COUNTERPARTIES PRIMARY KEY (COUNTERPARTY_ID)
  )

  RELATIONSHIPS (
    position_to_counterparty AS positions(COUNTERPARTY_ID) REFERENCES counterparties
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

    positions.instrument_type AS INSTRUMENT_TYPE
      WITH SYNONYMS ('instrument', 'instrument type', 'product type'),
    positions.exposure_class  AS EXPOSURE_CLASS
      WITH SYNONYMS ('Basel exposure class', 'risk-weight bucket', 'exposure class'),
    positions.as_of_date      AS AS_OF_DATE
      WITH SYNONYMS ('as of date', 'snapshot date', 'valuation date')
  )

  METRICS (
    -- Point-in-time exposure: additive across counterparties/instruments on a
    -- given AS_OF_DATE, NOT across dates. Always query with as_of_date as a
    -- dimension or filter — see semi_additive_metric pattern.
    positions.total_notional NON ADDITIVE BY (positions.as_of_date) AS SUM(NOTIONAL)
      WITH SYNONYMS ('total exposure', 'total notional', 'outstanding exposure', 'balance sheet exposure')
      COMMENT = 'Sum of NOTIONAL across counterparties/instruments for a given AS_OF_DATE. Non-additive across time — always filter or group by as_of_date.',

    positions.position_count AS COUNT(POSITION_ID)
      WITH SYNONYMS ('number of positions', 'position count'),

    -- Concentration check: each group's share of total book notional on the
    -- same AS_OF_DATE. Whole-table window (no PARTITION BY) so the
    -- denominator is always the full book, regardless of how the numerator
    -- is grouped.
    positions.pct_of_total_notional AS
      total_notional / SUM(total_notional) OVER ()
      WITH SYNONYMS ('concentration percentage', 'share of total exposure', 'exposure concentration')
      COMMENT = 'Each group''s share of total book notional (same AS_OF_DATE). Group by counterparties.name or counterparties.concentration_group to check single-name or group concentration limits.'
  )

  COMMENT = 'Balance-sheet exposure snapshot, synthesized bottom-up from HDFC Bank''s Basel III Pillar 3 disclosure. total_notional is semi-additive (point-in-time); pct_of_total_notional supports concentration-limit questions.'

  AI_SQL_GENERATION 'total_notional is a snapshot balance, not a transaction sum — ALWAYS include positions.as_of_date as a dimension or filter; summing across dates double-counts. Use pct_of_total_notional grouped by counterparties.name for single-counterparty concentration, or by counterparties.concentration_group for large-exposure-group concentration (the synthetic book flags the top 5% of counterparties by exposure as LARGE_EXPOSURE_TOP5PCT). Use positions.exposure_class for Basel risk-weight bucket breakdowns — note this field is a documented approximation (book-wide sampled proportions, not reconciled to a per-industry disclosure; see generator/anchors.py).';

GRANT USAGE ON SEMANTIC VIEW POSITIONS_SV TO ROLE ANALYST_READ;
