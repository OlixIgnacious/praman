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
--
-- Depends on sql/detectors/01_zscore_udf.sql existing first (entry_scale_zscore
-- calls the shared ZSCORE UDF) — run detectors before this file if deploying
-- from scratch; already true in this project's existing run order.

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

    -- Row-level fields, added after a real eval miss: Stage 2's basic
    -- ledger-integrity checks (sign/scale/duplicate/referential-integrity --
    -- see cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml's STAGE 2b) need to
    -- see individual entries, not just the aggregated METRICS below.
    -- entry_id/account_code/amount/position_id were previously only reachable
    -- inside METRICS' SUM(CASE...) expressions -- invisible to a question
    -- asking about one specific entry. POSITION_ID specifically: its absence
    -- here meant the agent could not check GL_ENTRIES against POSITIONS for
    -- a stale/orphaned reference at all (eval/results.md's stale_ref miss).
    gl_entries.entry_id AS ENTRY_ID
      WITH SYNONYMS ('entry id', 'GL entry', 'ledger entry'),
    gl_entries.account_code AS ACCOUNT_CODE
      WITH SYNONYMS ('account code', 'GL account'),
    gl_entries.amount AS AMOUNT
      WITH SYNONYMS ('entry amount', 'posted amount'),
    gl_entries.position_id AS POSITION_ID
      WITH SYNONYMS ('position id', 'position reference'),
    gl_entries.counterparty_id AS COUNTERPARTY_ID
      WITH SYNONYMS ('counterparty id', 'counterparty reference')
      COMMENT = 'The FK column itself, not the joined counterparties.name -- needed to PARTITION BY counterparty for the per-counterparty baseline metrics below.',

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
      COMMENT = 'npa_provisions / gross_npa. Expressed as a decimal — multiply by 100 for a percentage.',

    -- Per-counterparty scale baseline — added after eval/results.md's
    -- correct_but_anomalous false positive: a book-wide scale comparison
    -- can't tell "1000x the whole book's average" apart from "1000x this
    -- specific counterparty's own typical entry size," so it flagged a
    -- legitimately large entry from a large-exposure counterparty. This is
    -- the per-counterparty analogue, reusing the exact same ZSCORE UDF
    -- sql/detectors/ already shares between TRANSACTION_SIGNALS and
    -- GL_OUTLIER_SIGNALS -- a third consumer of the one shared formula, not
    -- a new one. Same trailing-window idiom as TRANSACTIONS_SV's
    -- window_metrics (ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING --
    -- baseline excludes the current entry, ordered by POSTING_DATE).
    gl_entries.entry_amount AS SUM(AMOUNT)
      WITH SYNONYMS ('row amount', 'entry amount metric')
      COMMENT = 'Row-level AMOUNT expressed as a metric -- at ENTRY_ID grain this equals the row''s own AMOUNT. Base for the trailing baseline below (same idiom as TRANSACTIONS_SV''s window metrics).',

    gl_entries.counterparty_account_baseline_mean AS
      AVG(entry_amount)
      OVER (PARTITION BY gl_entries.counterparty_id, gl_entries.account_code
            ORDER BY gl_entries.posting_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
      WITH SYNONYMS ('counterparty baseline amount', 'typical entry size for this counterparty')
      COMMENT = 'Mean of THIS counterparty''s own prior entries for the same ACCOUNT_CODE, excluding the current entry -- the per-counterparty analogue of a book-wide average.',

    gl_entries.counterparty_account_baseline_stddev AS
      STDDEV(entry_amount)
      OVER (PARTITION BY gl_entries.counterparty_id, gl_entries.account_code
            ORDER BY gl_entries.posting_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
      WITH SYNONYMS ('counterparty baseline volatility'),

    gl_entries.counterparty_account_baseline_count AS
      COUNT(entry_amount)
      OVER (PARTITION BY gl_entries.counterparty_id, gl_entries.account_code
            ORDER BY gl_entries.posting_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
      WITH SYNONYMS ('counterparty baseline entry count')
      COMMENT = 'Number of prior entries the baseline above is built from. Require >= 3 before trusting entry_scale_zscore -- a counterparty with only 1-2 other entries has no meaningful baseline (same minimum-history discipline as TRANSACTION_SIGNALS/GL_OUTLIER_SIGNALS).',

    gl_entries.entry_scale_zscore AS
      ZSCORE(entry_amount, counterparty_account_baseline_mean, counterparty_account_baseline_stddev)
      WITH SYNONYMS ('entry scale anomaly score', 'per-counterparty scale z-score')
      COMMENT = 'How many standard deviations this entry is from THIS counterparty''s own typical entry size for this account type. Use this, not a book-wide magnitude comparison, to judge scale anomalies -- only meaningful when counterparty_account_baseline_count >= 3.',

    gl_entries.is_entry_scale_outlier AS
      counterparty_account_baseline_count >= 3 AND ABS(entry_scale_zscore) >= 3
      WITH SYNONYMS ('is scale anomaly', 'per-counterparty scale flag')
      COMMENT = 'TRUE only with >=3 prior entries of baseline AND |z| >= 3 against THIS counterparty''s own norm. A counterparty with too little history is never flagged, same as TRANSACTION_SIGNALS/GL_OUTLIER_SIGNALS.'
  )

  COMMENT = 'Industry exposure and asset-quality (NPA) view over GL_ENTRIES, mirroring the Pillar 3 line items in LINE_ITEM_MAP. Read by Stage 0 (signal queries) and Stage 2 (assure-return peer/history benchmarks).'

  AI_SQL_GENERATION 'Use fund_based_exposure/nonfund_based_exposure for industry credit exposure questions, grouped by counterparties.sector. Use gross_npa grouped by gl_entries.npa_classification for the Substandard/Doubtful_1/Doubtful_2/Doubtful_3/Loss split — this matches LINE_ITEM_MAP.PILLAR3.NPA_CLASS.*. Use npa_ratio and provision_coverage_ratio for asset-quality questions; both are decimals, not pre-multiplied percentages. Do NOT sum fund_based_exposure and nonfund_based_exposure into a single "gross exposure" figure unless explicitly asked for a combined total — RBI disclosure and this project''s LINE_ITEM_MAP both treat them as separate line items. For ledger-integrity questions (sign errors, duplicate postings, orphaned position references), query entry_id/account_code/amount/position_id directly at row grain rather than through the aggregate METRICS above — e.g. WHERE account_code IN (''ADVANCES_FUND'',''ADVANCES_NONFUND'') AND amount < 0 for a sign check, or grouping by counterparty/position/account_code/amount together to surface duplicates. For scale/unit-anomaly questions specifically, use entry_scale_zscore/is_entry_scale_outlier (per-counterparty, per-account-code baseline) — NOT a book-wide magnitude comparison, which cannot tell a legitimately large counterparty''s own large entries apart from a genuine units error. Only trust these when counterparty_account_baseline_count >= 3; say so explicitly when it is not. A TRUE is_entry_scale_outlier alongside counterparties.concentration_group = ''LARGE_EXPOSURE_TOP5PCT'' is more likely a legitimately large position than a defect — corroborate with concentration_group before calling a scale outlier a probable error.';

GRANT SELECT ON SEMANTIC VIEW CREDIT_EXPOSURE_SV TO ROLE ANALYST_READ;
