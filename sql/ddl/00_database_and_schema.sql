-- Praman — database and schema layout.
-- Two schemas: CORE holds everything a Skill can read/write at runtime;
-- EVAL is isolated on purpose (see architecture.md, "Shared data model") —
-- INJECTED_CASES and EVAL_RESULTS must never be reachable by a Skill's
-- runtime role, or a bug could let the agent see its own answer key.

CREATE DATABASE IF NOT EXISTS PRAMAN
  COMMENT = 'Regulatory reporting + risk-signal copilot — Praman, Team Single Entry';

CREATE SCHEMA IF NOT EXISTS PRAMAN.CORE
  COMMENT = 'Governed tables every stage reads or writes at runtime';

CREATE SCHEMA IF NOT EXISTS PRAMAN.EVAL
  COMMENT = 'Eval ground truth and results — isolated, no grant to Skills runtime role';
