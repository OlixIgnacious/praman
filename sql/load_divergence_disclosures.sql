-- Loads PRAMAN.CORE.DIVERGENCE_DISCLOSURES from data/raw/divergence/ — Stage 2's
-- eval ground truth #1 (architecture.md): a real bank's own reported NPA/
-- provisioning vs. RBI's post-inspection assessment.
--
-- LINE_ITEM_ID mapping, and why it's a conceptual link, not a data join:
-- these are three different real banks, not our synthetic HDFC-anchored firm,
-- so there is no literal join to our GL_ENTRIES/COUNTERPARTIES here.
-- LINE_ITEM_ID means "which of our governed line-item definitions this
-- real-world divergence exemplifies" — PILLAR3.IND_NPA.GROSS / .PROVISIONS
-- (sql/seed_line_item_map.sql), the closest existing seeded rows, since both
-- are book-wide Gross NPA / provisioning figures, the same underlying
-- concept our line items compute at industry grain. Flagging the grain
-- mismatch here explicitly (book-wide real disclosure vs. our industry-
-- level TRANSFORM_LOGIC) rather than letting the FK imply a tighter fit
-- than actually exists — same convention as sql/seed_line_item_map.sql's
-- own header comment.
--
-- Only Bank of Baroda and Central Bank of India are loaded. YES Bank's
-- FY19 case (the most publicized of the three — ~₹3,277 cr headline
-- divergence) is deliberately excluded: the only source obtained
-- (data/raw/divergence/YES_Bank_divergence_disclosures_FY18_FY19.md,
-- secondary reporting only, per that file's own "Not obtained" section)
-- gives a total divergence figure but not a reliable REPORTED_VALUE /
-- RBI_ASSESSED_VALUE base pair — the ₹1,259 cr and ₹2,018 cr figures in
-- that source don't unambiguously resolve to "reported gross NPA" and
-- "RBI-assessed gross NPA" (their sum equals the headline ₹3,277 cr, but
-- so would several other readings, and REPORTED_VALUE/RBI_ASSESSED_VALUE
-- are NOT NULL here — better to leave the row out than guess and present
-- a guess as verified ground truth). BoB and Central Bank of India both
-- have clean, internally-consistent tabulated figures (reported +
-- divergence = assessed, exactly, in both sources) and are loaded as-is.
--
-- DISCLOSURE_DATE is NULL for both rows — only the disclosure month is
-- known from either source (BoB: December 2019; Central Bank of India:
-- November 2019), not the exact day, and fabricating a day would overstate
-- precision that isn't in the source.
--
-- Amounts converted from crore (as reported in source) to actual INR
-- (x 1e7), matching this project's convention elsewhere (generator/anchors.py
-- stores actual INR, not abbreviated units).

USE DATABASE PRAMAN;
USE SCHEMA CORE;

INSERT INTO DIVERGENCE_DISCLOSURES
  (DISCLOSURE_ID, BANK_NAME, FISCAL_YEAR, LINE_ITEM_ID, REPORTED_VALUE, RBI_ASSESSED_VALUE, DIVERGENCE_AMOUNT, DIVERGENCE_PCT, DISCLOSURE_DATE, SOURCE_DOCUMENT)
VALUES
  -- Bank of Baroda, FY19 (year ended 31 March 2019), Gross NPA:
  -- reported Rs69,924cr, RBI-assessed Rs75,174cr, divergence Rs5,250cr.
  -- DIVERGENCE_PCT = 5250 / 69924 * 100 = 7.5082 (recomputed precisely --
  -- an earlier draft of this file had 7.5088, a rounding slip; verified
  -- via `python3 -c "print(round(5250/69924*100, 4))"`).
  ('BOB_FY19_NPA', 'Bank of Baroda', 'FY19', 'PILLAR3.IND_NPA.GROSS',
   699240000000.00, 751740000000.00, 52500000000.00, 7.5082, NULL,
   'data/raw/divergence/Bank_of_Baroda_divergence_FY19.md'),

  -- Bank of Baroda, FY19, Provisioning: reported Rs46,001cr, RBI-assessed
  -- Rs50,091cr, divergence Rs4,090cr. DIVERGENCE_PCT = 4090 / 46001 * 100 =
  -- 8.8911 (recomputed precisely -- an earlier draft had 8.8933).
  ('BOB_FY19_PROVISIONS', 'Bank of Baroda', 'FY19', 'PILLAR3.IND_NPA.PROVISIONS',
   460010000000.00, 500910000000.00, 40900000000.00, 8.8911, NULL,
   'data/raw/divergence/Bank_of_Baroda_divergence_FY19.md'),

  -- Central Bank of India, FY19 (year ended 31 March 2019), Gross NPA:
  -- reported Rs32,356.04cr, RBI-assessed Rs34,921.04cr, divergence Rs2,565cr
  -- (34921.04 - 32356.04 = 2565.00 exactly, confirms the source figures are
  -- internally consistent). DIVERGENCE_PCT = 2565 / 32356.04 * 100 = 7.9274
  -- (recomputed precisely -- an earlier draft had 7.9280).
  ('CBI_FY19_NPA', 'Central Bank of India', 'FY19', 'PILLAR3.IND_NPA.GROSS',
   323560400000.00, 349210400000.00, 25650000000.00, 7.9274, NULL,
   'data/raw/divergence/Central_Bank_of_India_divergence_FY19.md');
