# Pending manual runs

Snowflake changes written but not yet executed — non-interactive `cortex exec` auto-denies mutating SQL, so these run in an interactive `cortex` session instead, where you approve each statement.

## Done

- ~~Semantic Views~~ (`TRANSACTIONS_SV`, `POSITIONS_SV`, `CREDIT_EXPOSURE_SV`) — deployed. Two fixes needed during deployment, now reflected in the source files: `GRANT USAGE` → `GRANT SELECT` (the correct privilege on a Semantic View), and `LIKE ... ESCAPE` → `STARTSWITH(...)` in `CREDIT_EXPOSURE_SV`.
- ~~Deterministic detectors~~ (`ZSCORE` UDF, `TRANSACTION_SIGNALS`, `GL_OUTLIER_SIGNALS`) — deployed.

Worth a quick look now that both are live (optional, not blocking anything):
- `SELECT * FROM TRANSACTION_SIGNALS WHERE IS_CANDIDATE_STRUCTURING ORDER BY STRUCTURING_SCORE DESC LIMIT 10;` — likely returns few or no rows, since no structuring cases have been injected into the synthetic data yet (that's an Eval-phase task, `plan.md` Days 15–17). Worth confirming the view *runs* cleanly, not that it flags anything.
- `SELECT * FROM GL_OUTLIER_SIGNALS WHERE IS_OUTLIER ORDER BY ABS(AMOUNT_ZSCORE) DESC LIMIT 10;` — same caveat.

The four `SKILL.md` files are already written too — Days 6–9 is now fully closed out.

## Still pending — the big one

**Spike a native Cortex Agent + CoWork, before building anything custom for Days 9–12.**

```
cortex -c reg_reporting_agent "Using the agent-studio skill, create a Cortex Agent over PRAMAN.CORE.TRANSACTIONS_SV, connect it to CoWork, and then run a test question against it end-to-end (e.g. 'what is the total transaction amount by channel') so we can see whether this actually works before building anything custom."
```

Context: `architecture.md`'s platform-capability note — a native `CREATE AGENT` object can attach Semantic Views/Cortex Search as tools directly, and CoWork (`ai.snowflake.com`) is a Snowflake-hosted chat UI that connects to it automatically on most accounts. If this holds up, Days 9–12 shrinks to Cortex Agent(s) + CoWork instead of a custom backend/frontend build. Not yet live-verified — this is now unblocked (`TRANSACTIONS_SV` exists).

If it works end-to-end: tell me and we'll replan Days 9–12 around it. If it doesn't: we fall back to the original custom backend/UI plan. Either way, tell me what happened.
