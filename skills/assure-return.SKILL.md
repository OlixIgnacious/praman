---
name: assure-return
title: Assure Return — Stage 2
summary: Validate a draft return against rule text, filing history, and peer benchmarks before an officer signs it — output is a ranked findings list, one entry per finding, each carrying a citation.
description: "Use before filing a draft regulatory return, to check it against rule text, the firm's own filing history, and peer benchmarks. Triggers: assure this return, validate draft return, check before filing, ranked findings, pre-filing review."
tools:
  - snowflake_sql_execute
  # TODO(backend, Days 9-12): confirm exact Cortex Search / Cortex Analyst
  # tool names — this skill retrieves rule text via RULE_CORPUS_SEARCH and
  # queries CREDIT_EXPOSURE_SV/POSITIONS_SV via Cortex Analyst, not raw SQL
  # against base tables.
language: en
status: Draft
author: Team Single Entry
type: snowflake
---

# Assure Return — Stage 2

## Overview

Stage 2 of the four-stage lifecycle. A draft return is about to be filed; this skill checks it before an officer signs off. Output is a **ranked list of findings**, one entry per finding — never a single pass/fail verdict — because a real reviewer needs to triage, not just be told "there's a problem somewhere."

The outlier detector here is **the same one Stage 0 uses** (`sql/detectors/README.md` — "one detector, two consumers"), applied at the `GL_ENTRIES`/`ACCOUNT_CODE` grain instead of the transaction grain. Don't re-derive anomaly scoring inline; query `GL_OUTLIER_SIGNALS`.

## Data this skill reads

- **`PRAMAN.CORE.LINE_ITEM_MAP`** — **only `STATUS = 'approved'` rows.** A `proposed` mapping hasn't been governance-reviewed; using it to validate a real filing would mean trusting an unreviewed aggregation rule for something with real regulatory liability. As of this project's current seed (`sql/seed_line_item_map.sql`), the 9 `PILLAR3.*` rows are still `proposed` — **this skill has nothing approved to validate against yet**, and should say so explicitly rather than silently falling back to the proposed rows.
- **`PRAMAN.CORE.RULE_CORPUS_SEARCH`** — the rule paragraph each line item's `RULE_CHUNK_ID` points to, for the citation on each finding.
- **`PRAMAN.CORE.CREDIT_EXPOSURE_SV` / `POSITIONS_SV`** — computing the actual value for a line item per its `TRANSFORM_LOGIC`, and peer/historical comparison.
- **`PRAMAN.CORE.GL_OUTLIER_SIGNALS`** — pre-computed monthly outlier flags per `ACCOUNT_CODE`, the shared detector.
- **`PRAMAN.CORE.DIVERGENCE_DISCLOSURES`** — real bank-reported-vs-RBI-assessed pairs; useful as calibration context for how large a divergence has historically triggered regulatory action (not a live check against the draft return itself — this table is Stage 2's *eval* ground truth, not a runtime input for a specific bank's filing).

## Workflow

1. **For each line item in the draft return**, look up its `LINE_ITEM_MAP` row. If none exists, or the existing row is `proposed`, that itself is a finding ("no approved mapping for this line item" / "mapping pending governance approval") — don't compute a value against an unapproved rule.
2. **Compute the expected value** from `TRANSFORM_LOGIC` via the relevant Semantic View, and compare against the draft return's stated value.
3. **Check `GL_OUTLIER_SIGNALS`** for the line item's underlying `ACCOUNT_CODE` — a mismatch AND a flagged outlier month is a higher-severity finding than a mismatch alone (both signals agreeing raises confidence something is genuinely wrong, not just an off-by-one mapping quirk).
4. **Retrieve the rule paragraph** (`RULE_CHUNK_ID`) for the citation.
5. **Rank findings** by severity: a value mismatch with a corroborating outlier flag ranks above a mismatch alone, which ranks above a stylistic/completeness note. Genuinely uncertain findings get **abstained**, not forced into a confident direction — `architecture.md`'s Evaluation architecture treats abstention as a first-class outcome, not a missing row, and this skill should behave the same way even before the eval harness exists to measure it.
6. **Write the `AUDIT_LOG` row.**

## Output shape

Ranked findings list, one entry per finding:
- `LINE_ITEM_ID`, draft value vs. computed value (or "no approved mapping" if that's the finding)
- Citation: **rule paragraph OR data lineage, per finding** (`architecture.md`'s stage table — not always the same citation type across findings in one run)
- Severity and confidence (including `abstained` as a valid state)
- Supporting signal, if any (`GL_OUTLIER_SIGNALS` flag)

## Audit logging

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, RETRIEVED_RULE_CHUNK_IDS, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (<uuid>, <analyst username>, '2', <the draft return identifier>, <model version>,
   ARRAY_CONSTRUCT(<every CHUNK_ID cited across all findings>), <the ranked findings list>,
   NULL, FALSE);
```

`HUMAN_DECISION` and `SIGNOFF_BY`/`SIGNOFF_AT` are set by the officer's actual sign-off action (a separate `AUDIT_LOG` insert under the `OFFICER_SIGNOFF` role — see `sql/rbac/04_officer_signoff.sql`'s header comment: a sign-off is a new row, never an `UPDATE` of this one).

## Common mistakes

- **Validating against a `proposed` `LINE_ITEM_MAP` row as if it were approved.** This is the single most important guardrail in this skill — check `STATUS` every time, don't cache an assumption that a mapping is approved from an earlier run.
- **Collapsing "no approved mapping exists yet" into a false negative.** That's a distinct, nameable finding ("mapping pending governance approval"), not silence and not a clean bill of health.
- **Re-implementing outlier scoring inline** instead of querying `GL_OUTLIER_SIGNALS` — this is exactly the drift "one detector, two consumers" exists to prevent.
- **One verdict for the whole return.** Every line item is its own finding with its own citation and severity; don't compress a multi-finding review into a single pass/fail sentence.
