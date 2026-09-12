-- GOVERNANCE_WRITE — approves LINE_ITEM_MAP rows (Stage 1 proposes with
-- STATUS='proposed'; only this role's holder flips a row to 'approved',
-- per the column comment in sql/ddl/02_line_item_map.sql) and commits new
-- RULE_CORPUS versions. SELECT on RULE_CORPUS included so a reviewer can
-- read the candidate rule chunk before approving the mapping it justifies.

USE ROLE SECURITYADMIN;

GRANT USAGE ON DATABASE PRAMAN TO ROLE GOVERNANCE_WRITE;
GRANT USAGE ON SCHEMA PRAMAN.CORE TO ROLE GOVERNANCE_WRITE;

-- Same real gap as ANALYST_READ (see that file's comment) -- no role had
-- warehouse USAGE, so none could execute a query at all. COMPUTE_WH is the
-- account's actual warehouse (sql/create_rule_corpus_search.sql).
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE GOVERNANCE_WRITE;

GRANT SELECT, INSERT, UPDATE ON TABLE PRAMAN.CORE.LINE_ITEM_MAP TO ROLE GOVERNANCE_WRITE;
GRANT SELECT, INSERT ON TABLE PRAMAN.CORE.RULE_CORPUS TO ROLE GOVERNANCE_WRITE;

-- GRANT ROLE GOVERNANCE_WRITE TO USER <username>;
