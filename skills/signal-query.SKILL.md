---
name: signal-query
title: Signal Query — Stage 0
summary: Answer a natural-language risk/fraud/liquidity question over PRAMAN's transaction, position, and exposure data, with structuring/velocity flags routed to compliance instead of resolved automatically.
description: "Use when an analyst asks a natural-language question about live risk, fraud, liquidity, or credit signals — e.g. 'why did our liquidity coverage ratio move 3pp this week', 'which counterparties look like structuring', 'flag credit exposures approaching concentration limits'. Triggers: signal, flag, why did, which counterparties, concentration, structuring, exposure, liquidity, LCR."
tools:
  - snowflake_sql_execute
  # TODO(backend, Days 9-12): confirm the exact Cortex Analyst query tool name
  # once the Agent SDK host is wired up — this skill queries the semantic
  # views below via Cortex Analyst, not by hand-writing SQL against the base
  # tables, but the concrete tool identifier isn't settled yet.
language: en
status: Draft
author: Team Single Entry
type: snowflake
---

# Signal Query — Stage 0

## Overview

Stage 0 of the four-stage lifecycle (`architecture.md`). An analyst asks a plain-language question; this skill answers it by querying the semantic layer, and — critically — never adjudicates. It flags candidates. AML-adjacent flags go to a compliance queue with full reasoning attached; tipping-off risk and STR liability stay with the human reviewer, always.

## Data this skill reads

- **`PRAMAN.CORE.TRANSACTIONS_SV`** — transaction volume/count/channel questions. Fully additive; safe to sum across any dimension.
- **`PRAMAN.CORE.POSITIONS_SV`** — exposure/concentration questions. `total_notional` is semi-additive (`NON ADDITIVE BY as_of_date`) — never sum it across dates. `pct_of_total_notional` is the concentration-limit metric.
- **`PRAMAN.CORE.CREDIT_EXPOSURE_SV`** — industry exposure / NPA / asset-quality questions.
- **`PRAMAN.CORE.TRANSACTION_SIGNALS`** — the structuring/velocity detector (`sql/detectors/`). `STRUCTURING_SCORE` and `IS_CANDIDATE_STRUCTURING` are pre-computed per counterparty per day; query this directly rather than re-deriving z-scores in an ad-hoc query.

Query via Cortex Analyst against the Semantic Views for anything a Semantic View covers — that's the point of building them (`sql/semantic_views/README.md`). Fall back to direct SQL against `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS` only for the detector outputs, which aren't (and shouldn't be) modeled as Semantic View metrics — they're already-scored signals, not raw aggregates.

## Workflow

1. **Classify the question** — which Semantic View(s) it needs, and whether it's AML-adjacent (structuring, sanctions-list proximity, unusual counterparty behavior) vs. a plain risk/liquidity/exposure question.
2. **Query.** Prefer the narrowest Semantic View that answers it. A question spanning transactions and exposure (e.g. "which large counterparties also show structuring") may need two queries joined on `COUNTERPARTY_ID`.
3. **If AML-adjacent:** do not present a confident verdict. Route to the compliance queue with the full query, retrieved data, and reasoning attached. The output to the analyst is "flagged for compliance review," not "this is structuring."
4. **If not AML-adjacent:** answer directly, citing the query and the underlying data (see Citation below).
5. **Write the `AUDIT_LOG` row** (below) before returning — every invocation, no exceptions.

## Citation

Per `architecture.md`'s stage table, Stage 0's citation type is **query + data lineage** — not a rule paragraph (that's Stage 1–3). Show the semantic view + metric(s) queried and the row-level data backing the answer; a follow-up "trace this further" question is Stage 3's job (lineage down to source GL/position rows), not this skill's.

## Escalation rules

- **AML-adjacent flags never auto-resolve, never auto-file.** Compliance queue only, per `architecture.md`'s System context ("tipping-off risk and STR liability stay entirely with the human reviewer").
- **Low-confidence structuring signals** (`STRUCTURING_SCORE` between 3 and 4, or `BASELINE_DAYS_OBSERVED` just over the 30-day minimum) should be presented with that caveat, not flattened into a flat yes/no.
- **A counterparty with `BASELINE_DAYS_OBSERVED < 30`** has no signal at all (`TRANSACTION_SIGNALS` won't flag them) — say "not enough history to assess," don't imply "clean."

## Audit logging

Every invocation writes one row, `IS_EVAL = FALSE` for real traffic:

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, QUERY_SNAPSHOT_ID, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (<uuid>, <analyst username>, '0', <the NL question>, <model version>, <a snapshot id for the query/result pair>, <the answer text>, NULL, FALSE);
```

`HUMAN_DECISION` stays `NULL` for Stage 0 — there's no accept/reject step here unless the question routed to compliance, in which case a follow-up row (or the compliance system's own log) records that outcome.

## Common mistakes

- **Summing `POSITIONS_SV.total_notional` across `as_of_date`.** It's a snapshot balance; the Semantic View's `NON ADDITIVE BY` guard exists precisely so a naive query doesn't silently double-count once a second snapshot date is loaded.
- **Treating `STRUCTURING_SCORE` as a fraud verdict.** It's a velocity/amount anomaly relative to the counterparty's own history — real, but not sufficient on its own. Pair with `RISK_RATING`, channel, and counterparty context before escalating language beyond "flagged for review."
- **Re-deriving an aggregate a Semantic View already exposes.** If `CREDIT_EXPOSURE_SV.npa_ratio` answers the question, use it — don't hand-write the `CASE WHEN ACCOUNT_CODE...` logic again inline; that's how the two copies drift.
