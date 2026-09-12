-- ANALYST_READ — every analyst (Stage 0/1/2/3 queries). Read-only, CORE only.
-- Includes COUNTERPARTIES/POSITIONS/GL_ENTRIES/TRANSACTIONS, not just
-- RULE_CORPUS/LINE_ITEM_MAP: Cortex Analyst Semantic Views query those
-- tables directly, so the role querying through them needs SELECT underneath.
-- DIVERGENCE_DISCLOSURES included — Stage 2 reads it for peer-benchmark
-- context; it is real historical disclosure, not the eval answer key
-- (that's INJECTED_CASES, in EVAL, never granted here).

USE ROLE SECURITYADMIN;

GRANT USAGE ON DATABASE PRAMAN TO ROLE ANALYST_READ;
GRANT USAGE ON SCHEMA PRAMAN.CORE TO ROLE ANALYST_READ;

-- Real gap found doing RBAC role-boundary verification, not caught earlier:
-- COMPUTE_WH is this account's actual warehouse (confirmed via SHOW WAREHOUSES,
-- see sql/create_rule_corpus_search.sql), and no role anywhere had USAGE on it.
-- Without this, ANALYST_READ cannot execute any query at all -- not raw SQL,
-- and not a Cortex Analyst/Agent-generated query either, since that still runs
-- as the calling role against real compute.
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ANALYST_READ;

GRANT SELECT ON TABLE PRAMAN.CORE.RULE_CORPUS TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.LINE_ITEM_MAP TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.COUNTERPARTIES TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.POSITIONS TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.GL_ENTRIES TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.TRANSACTIONS TO ROLE ANALYST_READ;
GRANT SELECT ON TABLE PRAMAN.CORE.DIVERGENCE_DISCLOSURES TO ROLE ANALYST_READ;

-- GRANT ROLE ANALYST_READ TO USER <username>;
