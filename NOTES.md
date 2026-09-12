# Pending manual runs

Snowflake changes written but not yet executed — non-interactive `cortex exec` auto-denies mutating SQL, so these run in an interactive `cortex` session instead, where you approve each statement.

## Done

- Semantic Views (`TRANSACTIONS_SV`, `POSITIONS_SV`, `CREDIT_EXPOSURE_SV`) and the shared detector (`ZSCORE`, `TRANSACTION_SIGNALS`, `GL_OUTLIER_SIGNALS`) — deployed.
- **Cortex Agent + CoWork spike — confirmed working.** `PRAMAN.CORE.TRANSACTIONS_AGENT` live at `ai.snowflake.com`, correct live answers over `TRANSACTIONS_SV`. Days 9–12 is proceeding on this path instead of a custom backend/UI build — see `architecture.md`'s platform-capability note and restructured build plan.

## Nothing currently pending

Next up (`plan.md`, Days 9–12): extend the agent to cover `POSITIONS_SV`/`CREDIT_EXPOSURE_SV`/`RULE_CORPUS_SEARCH`, decide one-agent-vs-many, then scope the remaining custom backend to `AUDIT_LOG` writes + Stage 1/3 orchestration. Nothing here needs your interactive-session approval right this moment — I'll add items back here once there's a concrete SQL/agent-spec change ready to run.
