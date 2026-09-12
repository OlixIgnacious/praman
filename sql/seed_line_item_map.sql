-- Seed LINE_ITEM_MAP for the Pillar 3 line items generator/generate_synthetic_data.py
-- exactly reconciles (see its module docstring): industry-wise fund/non-fund
-- exposure, industry-wise gross NPA, industry-wise NPA provisions, and the
-- book-wide NPA classification split. These 9 rows are exactly that list —
-- deliberately not one row per industry: a line item here is a report
-- metric/aggregation rule, and per-industry breakdown is expressed as a
-- GROUP BY in TRANSFORM_LOGIC, not enumerated as separate rows.
--
-- LINE_ITEM_ID is assigned internally (RBI has no public DPM/MDRM-equivalent
-- code list — see the column comment in sql/ddl/02_line_item_map.sql).
--
-- RULE_CHUNK_ID citation, and its honest limit: RBI/DoS/2026-27/415#21 (the
-- "List of Applicable Returns" table) is the only ingested rule text that
-- identifies which return carries this data — RAQ's description there reads
-- "asset classification and provisioning for the advances and investment
-- portfolio... sector-wise granular break up of credit and investment
-- portfolio," which is exactly NPA classification/provisions/exposure by
-- industry. It is NOT the actual Basel III Pillar 3 disclosure norms circular
-- (that document isn't in RULE_CORPUS yet) — it only establishes that a
-- return containing this class of data must exist and be filed. Treat this
-- citation as "why we track this," not "the precise disclosure format rule."
--
-- STATUS is 'proposed', not 'approved', on every row here deliberately: per
-- the maker-checker design (architecture.md, "Deployment & security"), only
-- GOVERNANCE_WRITE flipping STATUS to 'approved' after reviewing the citation
-- above should commit these — a seeding script isn't the human approval step.

USE DATABASE PRAMAN;
USE SCHEMA CORE;

INSERT INTO LINE_ITEM_MAP
  (LINE_ITEM_ID, REPORT_NAME, TAXONOMY_VERSION, DESCRIPTION, SOURCE_TABLE, SOURCE_COLUMN, TRANSFORM_LOGIC, RULE_CHUNK_ID, STATUS, VALID_FROM)
VALUES
  ('PILLAR3.IND_EXPOSURE.FUND', 'Basel III Pillar 3 Disclosure', NULL,
   'Industry-wise fund-based credit exposure (p.8 of the HDFC Bank Pillar 3 disclosure, data/raw/pillar3/)',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''ADVANCES_FUND'' OR (ACCOUNT_CODE LIKE ''NPA\_%'' ESCAPE ''\'' AND ACCOUNT_CODE <> ''NPA_PROVISION''), JOIN COUNTERPARTIES ON GL_ENTRIES.COUNTERPARTY_ID = COUNTERPARTIES.COUNTERPARTY_ID, GROUP BY COUNTERPARTIES.SECTOR — includes both performing (ADVANCES_FUND) and non-performing (NPA_*) fragments of the same fund-based book',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.IND_EXPOSURE.NONFUND', 'Basel III Pillar 3 Disclosure', NULL,
   'Industry-wise non-fund-based credit exposure (p.8 of the HDFC Bank Pillar 3 disclosure)',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''ADVANCES_NONFUND'', JOIN COUNTERPARTIES ON GL_ENTRIES.COUNTERPARTY_ID = COUNTERPARTIES.COUNTERPARTY_ID, GROUP BY COUNTERPARTIES.SECTOR',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.IND_NPA.GROSS', 'Basel III Pillar 3 Disclosure', NULL,
   'Industry-wise gross NPA (p.11 of the HDFC Bank Pillar 3 disclosure)',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE LIKE ''NPA\_%'' ESCAPE ''\'' AND ACCOUNT_CODE <> ''NPA_PROVISION'', JOIN COUNTERPARTIES ON GL_ENTRIES.COUNTERPARTY_ID = COUNTERPARTIES.COUNTERPARTY_ID, GROUP BY COUNTERPARTIES.SECTOR',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.IND_NPA.PROVISIONS', 'Basel III Pillar 3 Disclosure', NULL,
   'Industry-wise NPA provisions, derived from each industry''s real disclosed coverage ratio (p.11)',
   'GL_ENTRIES', 'AMOUNT',
   '-SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_PROVISION'' (stored as a negative amount), JOIN COUNTERPARTIES ON GL_ENTRIES.COUNTERPARTY_ID = COUNTERPARTIES.COUNTERPARTY_ID, GROUP BY COUNTERPARTIES.SECTOR',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.NPA_CLASS.SUBSTANDARD', 'Basel III Pillar 3 Disclosure', NULL,
   'Book-wide NPA classification — Substandard (p.10, "Classification of Gross NPAs")',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_SUBSTANDARD'' — book-wide total, not grouped by industry (real disclosure gives only the aggregate split; see generator/anchors.py NPA_CLASSIFICATION_SHARE)',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.NPA_CLASS.DOUBTFUL_1', 'Basel III Pillar 3 Disclosure', NULL,
   'Book-wide NPA classification — Doubtful 1 (p.10, "Classification of Gross NPAs")',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_DOUBTFUL_1'' — book-wide total, not grouped by industry',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.NPA_CLASS.DOUBTFUL_2', 'Basel III Pillar 3 Disclosure', NULL,
   'Book-wide NPA classification — Doubtful 2 (p.10, "Classification of Gross NPAs")',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_DOUBTFUL_2'' — book-wide total, not grouped by industry',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.NPA_CLASS.DOUBTFUL_3', 'Basel III Pillar 3 Disclosure', NULL,
   'Book-wide NPA classification — Doubtful 3 (p.10, "Classification of Gross NPAs")',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_DOUBTFUL_3'' — book-wide total, not grouped by industry',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30'),

  ('PILLAR3.NPA_CLASS.LOSS', 'Basel III Pillar 3 Disclosure', NULL,
   'Book-wide NPA classification — Loss (p.10, "Classification of Gross NPAs")',
   'GL_ENTRIES', 'AMOUNT',
   'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''NPA_LOSS'' — book-wide total, not grouped by industry',
   'RBI/DoS/2026-27/415#21', 'proposed', '2026-06-30');
