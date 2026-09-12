-- CREDIT_EXPOSURE_SV — industry exposure and asset-quality (NPA) view over
-- GL_ENTRIES, deliberately mirroring the Pillar 3 line items seeded into
-- LINE_ITEM_MAP (sql/seed_line_item_map.sql): fund/non-fund exposure, gross
-- NPA, provisions, and NPA classification. Same underlying aggregation
-- logic, expressed here as live queryable Cortex Analyst metrics instead of
-- LINE_ITEM_MAP's TRANSFORM_LOGIC text — the two should stay in sync if
-- either changes.
--
-- Forked from semantic-view-patterns' derived_metrics pattern (ratio metrics
-- referencing other metrics by name) and entity_facts (computed/categorical
-- dimensions from a CASE expression). ACCOUNT_CODE conventions are
-- generator/generate_synthetic_data.py's: 'ADVANCES_FUND' / 'ADVANCES_NONFUND'
-- (performing), 'NPA_<classification>' (non-performing), 'NPA_PROVISION'
-- (contra-account, stored as a negative amount). NPA only applies to the
-- fund-based book (generator note: "non-fund book: no NPA overlay") — so
-- npa_ratio divides by fund_based_exposure, not a combined total.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

CREATE OR REPLACE SEMANTIC VIEW CREDIT_EXPOSURE_SV

  TABLES (
    gl_entries     AS GL_ENTRIES     PRIMARY KEY (ENTRY_ID),
    counterparties AS COUNTERPARTIES PRIMARY KEY (COUNTERPARTY_ID)
  )

  RELATIONSHIPS (
    gl_to_counterparty AS gl_entries(COUNTERPARTY_ID) REFERENCES counterparties
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

    gl_entries.posting_date AS POSTING_DATE
      WITH SYNONYMS ('posting date', 'GL date'),

    -- Categorical view of ACCOUNT_CODE — mirrors LINE_ITEM_MAP's PILLAR3.*
    -- line items so an analyst can ask "gross NPA by classification" instead
    -- of knowing the raw account code convention.
    gl_entries.exposure_type AS (
      CASE
        WHEN ACCOUNT_CODE = 'ADVANCES_FUND'    THEN 'PERFORMING_FUND'
        WHEN ACCOUNT_CODE = 'ADVANCES_NONFUND' THEN 'NONFUND'
        WHEN ACCOUNT_CODE = 'NPA_PROVISION'    THEN 'NPA_PROVISION'
        WHEN STARTSWITH(ACCOUNT_CODE, 'NPA_')  THEN 'NPA'
        ELSE ACCOUNT_CODE
      END
    )
      WITH SYNONYMS ('exposure type', 'account category', 'performing or non-performing'),

    gl_entries.npa_classification AS (
      CASE
        WHEN STARTSWITH(ACCOUNT_CODE, 'NPA_') AND ACCOUNT_CODE <> 'NPA_PROVISION'
          THEN REPLACE(ACCOUNT_CODE, 'NPA_', '')
        ELSE NULL
      END
    )
      WITH SYNONYMS ('NPA classification', 'asset classification', 'NPA category', 'substandard doubtful loss')
  )

  METRICS (
    -- These four mirror PILLAR3.IND_EXPOSURE.FUND/NONFUND and
    -- PILLAR3.IND_NPA.GROSS/PROVISIONS in LINE_ITEM_MAP exactly.
    gl_entries.fund_based_exposure AS
      SUM(CASE WHEN ACCOUNT_CODE = 'ADVANCES_FUND'
                 OR (STARTSWITH(ACCOUNT_CODE, 'NPA_') AND ACCOUNT_CODE <> 'NPA_PROVISION')
               THEN AMOUNT ELSE 0 END)
      WITH SYNONYMS ('fund-based exposure', 'fund based credit exposure')
      COMMENT = 'Performing (ADVANCES_FUND) + non-performing (NPA_*) fragments of the same fund-based book. Matches LINE_ITEM_MAP.PILLAR3.IND_EXPOSURE.FUND.',

    gl_entries.nonfund_based_exposure AS
      SUM(CASE WHEN ACCOUNT_CODE = 'ADVANCES_NONFUND' THEN AMOUNT ELSE 0 END)
      WITH SYNONYMS ('non-fund based exposure', 'non fund exposure', 'contingent exposure')
      COMMENT = 'Matches LINE_ITEM_MAP.PILLAR3.IND_EXPOSURE.NONFUND. No NPA overlay applies to this book.',

    gl_entries.gross_npa AS
      SUM(CASE WHEN STARTSWITH(ACCOUNT_CODE, 'NPA_') AND ACCOUNT_CODE <> 'NPA_PROVISION'
               THEN AMOUNT ELSE 0 END)
      WITH SYNONYMS ('gross NPA', 'non-performing assets', 'bad loans')
      COMMENT = 'Matches LINE_ITEM_MAP.PILLAR3.IND_NPA.GROSS. Group by gl_entries.npa_classification for the Substandard/Doubtful/Loss split.',

    gl_entries.npa_provisions AS
      -SUM(CASE WHEN ACCOUNT_CODE = 'NPA_PROVISION' THEN AMOUNT ELSE 0 END)
      WITH SYNONYMS ('NPA provisions', 'loan loss provisions', 'provisioning')
      COMMENT = 'NPA_PROVISION rows are stored as negative amounts; this metric returns a positive provisions figure. Matches LINE_ITEM_MAP.PILLAR3.IND_NPA.PROVISIONS.',

    -- Ratios — derived from the metrics above by bare name, per the
    -- derived_metrics pattern. Divided by fund_based_exposure specifically,
    -- since NPA never applies to the non-fund book.
    gl_entries.npa_ratio AS
      gross_npa / NULLIF(fund_based_exposure, 0)
      WITH SYNONYMS ('NPA ratio', 'gross NPA ratio', 'asset quality ratio', 'bad loan ratio')
      COMMENT = 'gross_npa / fund_based_exposure. Expressed as a decimal — multiply by 100 for a percentage.',

    gl_entries.provision_coverage_ratio AS
      npa_provisions / NULLIF(gross_npa, 0)
      WITH SYNONYMS ('provision coverage ratio', 'coverage ratio', 'PCR')
      COMMENT = 'npa_provisions / gross_npa. Expressed as a decimal — multiply by 100 for a percentage.'
  )

  COMMENT = 'Industry exposure and asset-quality (NPA) view over GL_ENTRIES, mirroring the Pillar 3 line items in LINE_ITEM_MAP. Read by Stage 0 (signal queries) and Stage 2 (assure-return peer/history benchmarks).'

  AI_SQL_GENERATION 'Use fund_based_exposure/nonfund_based_exposure for industry credit exposure questions, grouped by counterparties.sector. Use gross_npa grouped by gl_entries.npa_classification for the Substandard/Doubtful_1/Doubtful_2/Doubtful_3/Loss split — this matches LINE_ITEM_MAP.PILLAR3.NPA_CLASS.*. Use npa_ratio and provision_coverage_ratio for asset-quality questions; both are decimals, not pre-multiplied percentages. Do NOT sum fund_based_exposure and nonfund_based_exposure into a single "gross exposure" figure unless explicitly asked for a combined total — RBI disclosure and this project''s LINE_ITEM_MAP both treat them as separate line items.';

GRANT SELECT ON SEMANTIC VIEW CREDIT_EXPOSURE_SV TO ROLE ANALYST_READ;
