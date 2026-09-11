-- AUDIT_INSERT — the backend service's logging identity. Every Skill
-- invocation writes one AUDIT_LOG row as this role. Deliberately no SELECT,
-- UPDATE, or DELETE grant: this role can add rows and read nothing back,
-- which is enough for logging and removes any need to trust it not to
-- tamper with prior rows. No role anywhere in this repo is ever granted
-- UPDATE/DELETE on AUDIT_LOG — that is what makes "append-only" an
-- enforced grant rather than a policy statement (sql/ddl/09_audit_log.sql).

USE ROLE SECURITYADMIN;

GRANT USAGE ON DATABASE PRAMAN TO ROLE AUDIT_INSERT;
GRANT USAGE ON SCHEMA PRAMAN.CORE TO ROLE AUDIT_INSERT;

GRANT INSERT ON TABLE PRAMAN.CORE.AUDIT_LOG TO ROLE AUDIT_INSERT;

-- GRANT ROLE AUDIT_INSERT TO USER <backend_service_user>;
