-- OFFICER_SIGNOFF — the signing/compliance officer's maker-checker identity.
-- Grant is identical to AUDIT_INSERT (INSERT-only on AUDIT_LOG) by design,
-- not an oversight: a sign-off is recorded as a *new* AUDIT_LOG row
-- (HUMAN_DECISION, SIGNOFF_BY, SIGNOFF_AT populated, RUN_ID referencing the
-- run being signed off on) rather than an UPDATE of that run's original row.
-- Keeping this a distinct role — not just reusing AUDIT_INSERT — is what
-- lets Snowflake's own role grants show who is authorized to record a
-- sign-off, separate from who the backend service logs as day to day.

USE ROLE SECURITYADMIN;

GRANT USAGE ON DATABASE PRAMAN TO ROLE OFFICER_SIGNOFF;
GRANT USAGE ON SCHEMA PRAMAN.CORE TO ROLE OFFICER_SIGNOFF;

GRANT INSERT ON TABLE PRAMAN.CORE.AUDIT_LOG TO ROLE OFFICER_SIGNOFF;

-- GRANT ROLE OFFICER_SIGNOFF TO USER <signing_officer_username>;
