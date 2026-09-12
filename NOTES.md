# Pending manual runs

Snowflake changes I've written but haven't executed — non-interactive `cortex exec` auto-denies mutating SQL, so these need to run where you can approve each statement. Run in order (each depends on the previous).

## 1. Semantic Views

```
cortex -c reg_reporting_agent "Read and execute sql/semantic_views/01_transactions_sv.sql, then 02_positions_sv.sql, then 03_credit_exposure_sv.sql, in order."
```

Creates `TRANSACTIONS_SV`, `POSITIONS_SV`, `CREDIT_EXPOSURE_SV` and grants `ANALYST_READ` `USAGE` on each. Design notes: `sql/semantic_views/README.md`.

## 2. Deterministic detectors

```
cortex -c reg_reporting_agent "Read and execute sql/detectors/01_zscore_udf.sql, then 02_transaction_signals.sql, then 03_gl_outlier_signals.sql, in order."
```

Creates the `ZSCORE` UDF and the `TRANSACTION_SIGNALS` / `GL_OUTLIER_SIGNALS` views, grants `ANALYST_READ` access to all three. Design notes: `sql/detectors/README.md`.

## After running both

Tell me and I'll check them off in `plan.md`/`TRACKER.md`. Worth a quick look before moving on:

- `SELECT * FROM TRANSACTION_SIGNALS WHERE IS_CANDIDATE_STRUCTURING ORDER BY STRUCTURING_SCORE DESC LIMIT 10;` — likely returns few or no rows right now, since no structuring cases have been injected into the synthetic data yet (that's an Eval-phase task, `plan.md` Days 15–17). Worth confirming the view *runs* cleanly, not that it flags anything yet.
- `SELECT * FROM GL_OUTLIER_SIGNALS WHERE IS_OUTLIER ORDER BY ABS(AMOUNT_ZSCORE) DESC LIMIT 10;` — same caveat.

The four `SKILL.md` files (`signal-query`, `circular-interpret`, `assure-return`, `narrative-draft`) are already written — that closes out Days 6–9 once the two runs above land.

## 3. Big one — spike a native Cortex Agent + CoWork (do this after 1 and 2)

Found something that could significantly cut down the Days 9–12 backend/UI build: Snowflake has a native **Cortex Agent** object (`CREATE AGENT`) — a declarative object you attach Semantic Views and Cortex Search services to as tools, no custom orchestration code — and **CoWork** (`ai.snowflake.com`, formerly Snowflake Intelligence) is a Snowflake-hosted end-user chat UI that connects to an agent automatically on most accounts. That's potentially most of "backend + review UI" already built by the platform. Full writeup: `architecture.md`'s new platform-capability note (in "Platform capability notes") and the restructured Days 9–12 build plan there.

**Not yet verified live** — found via the bundled `agent-studio` skill's docs, not tested, and blocked on `TRANSACTIONS_SV` actually existing (step 1 above). Once that's run:

```
cortex -c reg_reporting_agent "Using the agent-studio skill, create a Cortex Agent over PRAMAN.CORE.TRANSACTIONS_SV, connect it to CoWork, and then run a test question against it end-to-end (e.g. 'what is the total transaction amount by channel') so we can see whether this actually works before building anything custom."
```

If that works end-to-end, tell me and we'll replan Days 9–12 around Cortex Agent(s) + CoWork instead of a custom backend/frontend. If it doesn't, we fall back to the original custom build — either way, tell me what happened and I'll take it from there.
