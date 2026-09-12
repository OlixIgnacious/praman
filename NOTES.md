# Pending manual runs

Snowflake changes written but not yet executed — non-interactive `cortex exec` auto-denies mutating SQL, so these run in an interactive `cortex` session instead, where you approve each statement.

## Done

- Semantic Views, the shared detector, and the `TRANSACTIONS_AGENT` spike — all deployed and confirmed working (see `TRACKER.md`/`plan.md` for detail).

## Pending, in order

### 1. Audit-log stored procedure

```
cortex -c reg_reporting_agent "Read and execute sql/procedures/01_sp_write_audit_log.sql."
```

Creates `SP_WRITE_AUDIT_LOG`, transfers ownership to `AUDIT_INSERT`, grants `ANALYST_READ` `USAGE` on it. Must run before step 2 — the new agent's `write_audit_log` tool points at this procedure. Design rationale: `sql/procedures/README.md`.

### 2. Deploy the combined Stage 0 + Stage 2 agent

```
cortex -c reg_reporting_agent "Using the agent-studio skill, deploy the agent spec at cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml as PRAMAN.CORE.SIGNAL_ASSURE_AGENT, then grant USAGE ON AGENT PRAMAN.CORE.SIGNAL_ASSURE_AGENT to ROLE ANALYST_READ and to ROLE ACCOUNTADMIN, then connect it to CoWork."
```

This replaces `TRANSACTIONS_AGENT` (the earlier single-tool spike) with a 5-tool agent covering both stages — see `.claude/plans/lets-decide-what-would-rippling-lighthouse.md` for the full design (why combined, the tool list, the two-block orchestration instructions, the audit-logging reliability risk).

### 3. Verify live in CoWork before calling this done

Run each of these as a real question against the agent in CoWork, then check `AUDIT_LOG`:

- Plain Stage 0 volume/channel question (regression check against the original spike) — still answers correctly.
- A Stage 0 concentration question — routes to `position_analytics`, respects the `as_of_date` guard on `total_notional`. Watch the generated-SQL trace for the same metric-name-fallback quirk noted on the original spike.
- A Stage 0 question phrased to look AML-adjacent ("which counterparties look like structuring") — produces a "flagged for compliance review" answer, not a verdict.
- A Stage 2 question validating any of the 9 seeded `LINE_ITEM_MAP` rows — **the single most important check**: should return "no approved mapping / pending governance approval," not a silently-computed value, since every seeded row is still `STATUS='proposed'`.
- A Stage 2 question that should trigger `rule_corpus_search` for a citation — confirm it does.
- Then: `SELECT * FROM AUDIT_LOG WHERE RUN_TIMESTAMP > <test start time> ORDER BY RUN_TIMESTAMP;` — expect exactly one row per test question above, with the correct `STAGE` value ('0' or '2'). This is the check that actually matters most — the audit-log tool call is something the model *chooses* to make, not a guaranteed hook, so this is the only way to know the compliance-critical audit trail is actually being written every time.

### 4. Once verification passes: retire the spike

```
cortex -c reg_reporting_agent "DROP AGENT PRAMAN.CORE.TRANSACTIONS_AGENT;"
```

Then remove its entry from `cortex_project/cortex-project.yaml` and delete `cortex_project/TRANSACTIONS_AGENT.agent.yaml`, so CoWork doesn't show two overlapping agents answering the same questions.

Tell me the results of each step (especially step 3's `AUDIT_LOG` check) and I'll update `plan.md`/`TRACKER.md`.
