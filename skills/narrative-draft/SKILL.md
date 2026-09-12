---
name: narrative-draft
description: "Trace a confirmed break or signal to ranked root causes via native Snowflake lineage, then draft a remediation and a regulator/compliance-facing narrative -- a thin orchestration layer over lineage tracing, not a custom lineage build. Use when a confirmed finding (from assure-return or signal-query, never a raw unconfirmed flag) needs root-cause tracing and a draft explanation. Triggers: trace this, root cause, why did this break, draft narrative, explain this finding, lineage trace, upstream source, downstream impact."
summary: Trace a confirmed break or signal to ranked root causes via native lineage, then draft a remediation and a regulator/compliance-facing narrative — a thin layer over Snowflake's own lineage tracing, not a custom lineage build.
---

# Narrative Draft — Stage 3

## Overview

Stage 3 of the four-stage lifecycle, and deliberately the thinnest skill of the four. Per `architecture.md`'s Day 1 spike (`cortex lineage SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS` confirmed working on this account's Enterprise edition), native lineage tracing is close to off-the-shelf for this stage's core need — most of Stage 3's real work is the bundled governance lineage capability, prompted directly, not a custom lineage implementation. This skill's job is orchestration around that: take a confirmed break/signal in, get a lineage trace out, turn it into ranked root causes, a remediation, and a draft narrative.

`cortex lineage` traces from a table/view, not a Semantic View — trace from the base table (`GL_ENTRIES`, `POSITIONS`) and read its downstream, not from `CREDIT_EXPOSURE_SV` directly (`demos/stage3_lineage_walkthrough.md` is the worked example: `GL_ENTRIES` → `CREDIT_EXPOSURE_SV` → `SIGNAL_ASSURE_AGENT`, confirmed fully traceable).

**Never send the narrative to a regulator or compliance system directly.** Draft only — human sign-off before use, always (`architecture.md`'s Who it is for: "accountability is unchanged... never an autonomous filer").

## Inputs

- A confirmed break from `assure-return` (a specific `LINE_ITEM_ID`/`ACCOUNT_CODE` finding, not a proposed/unreviewed one), or
- A confirmed signal from `signal-query` (something already past the compliance queue's own review, not a raw flag straight from `TRANSACTION_SIGNALS`).

If the input is still a *candidate* (not yet confirmed by a human or the compliance queue), that's a sign this skill was invoked too early — escalate back rather than tracing lineage on an unconfirmed finding.

## Workflow

1. **Identify the report line item or source row(s) at the center of the confirmed finding.**
2. **Trace lineage** using the account's native lineage capability (`cortex lineage <fully-qualified base table/view>` — same command form as the Day 1 spike) — downstream from the source table to see what it feeds, and upstream to the source `GL_ENTRIES`/`POSITIONS` rows that produced a given report figure.
3. **Rank candidate root causes** from the trace: a single upstream source that changed recently outranks a diffuse set of many small contributing entries; a source with a known `INJECTED_CASE_ID` (the eval catalogue, `eval/README.md` — 9 planted cases across `GL_ENTRIES`/`TRANSACTIONS`) would be a strong candidate when tracing an eval scenario, but don't invent that signal for a real (non-eval) finding where no such catalogue exists.
4. **Retrieve the relevant rule paragraph** (`RULE_CORPUS_SEARCH`) for remediation basis — e.g. if the root cause is a misclassified NPA entry, cite the paragraph governing that classification.
5. **Draft the narrative** — plain, factual, citing both the lineage trace and the rule basis. Write it as what a compliance officer or regulator would need to read, not as an internal debugging note.
6. **Write the `AUDIT_LOG` row.** Everything from this skill is a draft; `HUMAN_DECISION`/`SIGNOFF_BY`/`SIGNOFF_AT` are populated later, by an actual officer action via `SP_RECORD_SIGNOFF` (`sql/procedures/02_sp_record_signoff.sql`), never by this skill.

## Output shape

- Ranked root causes, each tied to a specific upstream row/entry from the lineage trace
- Proposed remediation (what should change, and where)
- Draft narrative (regulator-facing or compliance-facing, depending on the trigger)

## Citation

Stage 3's citation type is **lineage trace + rule citation** (`architecture.md`'s stage table) — every root cause claim should be traceable to specific upstream rows via the lineage trace, and every remediation claim should cite the rule paragraph it's grounded in.

## Audit logging

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, RETRIEVED_RULE_CHUNK_IDS, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (<uuid>, <analyst username>, '3', <the confirmed break/signal that triggered this>, <model version>,
   ARRAY_CONSTRUCT(<every CHUNK_ID cited in the remediation basis>), <root causes + remediation + draft narrative>,
   NULL, FALSE);
```

## Common mistakes

- **Reimplementing lineage tracing instead of calling the native capability.** The entire point of this skill being thin is that Snowflake's own lineage graph already does the hard part — don't hand-roll a GL/position join chain that duplicates what `cortex lineage` already returns.
- **Tracing lineage directly against a Semantic View.** `cortex lineage` needs a base table/view — trace from `GL_ENTRIES`/`POSITIONS`, not `CREDIT_EXPOSURE_SV`, a real platform limitation found live (`demos/stage3_lineage_walkthrough.md`).
- **Tracing lineage on an unconfirmed candidate.** This skill exists for *confirmed* breaks/signals; a raw `TRANSACTION_SIGNALS` flag or an `assure-return` finding still awaiting review isn't ready for this stage yet.
- **Letting the draft narrative read as a final document.** It's a draft for a human to review, edit, and sign off on — never phrase it as something already sent or already true, since it hasn't been signed off yet when this skill produces it.
