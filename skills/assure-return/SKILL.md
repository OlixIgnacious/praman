---
name: assure-return
description: "Validate a draft regulatory return against rule text, filing history, and peer/self benchmarks before an officer signs it, producing a ranked findings list (never a single pass/fail verdict), each finding carrying a citation. Use before filing any draft return, or when asked to check a line item's value, flag sign/scale/duplicate/referential-integrity errors, or corroborate an anomaly against outlier history. Triggers: assure this return, validate draft return, check before filing, ranked findings, pre-filing review, sign error, scale anomaly, duplicate posting, stale reference, is this NPA figure right, LINE_ITEM_MAP approved."
summary: Validate a draft return against rule text, filing history, and peer benchmarks before an officer signs it — output is a ranked findings list, one entry per finding, each carrying a citation.
---

# Assure Return — Stage 2

## Overview

Stage 2 of the four-stage lifecycle. A draft return is about to be filed; this skill checks it before an officer signs off. Output is a **ranked list of findings**, one entry per finding — never a single pass/fail verdict — because a real reviewer needs to triage, not just be told "there's a problem somewhere."

The outlier detector here is **the same one Stage 0 uses** (`sql/detectors/README.md` — "one detector, two consumers"), applied at the `GL_ENTRIES`/`ACCOUNT_CODE` grain instead of the transaction grain. Don't re-derive anomaly scoring inline; query `GL_OUTLIER_SIGNALS`.

**Two distinct kinds of check, deliberately split (`cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml`'s Stage 2a/2b):**
- **2a — line-item value validation.** Requires an `approved` `LINE_ITEM_MAP` row — computing a governed aggregation rule's value is exactly the thing governance approval exists to control.
- **2b — basic ledger-integrity checks** (sign, scale, duplicate, referential-integrity). These are raw-data sanity checks, not "computing an approved line item's value," so they don't need `LINE_ITEM_MAP` approval — a real eval miss (`eval/results.md`) found the gate over-applying to this category and blocking legitimate integrity checks that should always run.

## Data this skill reads

- **`PRAMAN.CORE.LINE_ITEM_MAP`** — **only `STATUS = 'approved'` rows for 2a.** A `proposed` mapping hasn't been governance-reviewed; using it to validate a real filing would mean trusting an unreviewed aggregation rule for something with real regulatory liability. Check `STATUS` per line item, never assume the whole seed set is in one state.
- **Query `LINE_ITEM_MAP` via a real tool, not an assumed default.** `PRAMAN.CORE.SIGNAL_ASSURE_AGENT`'s first deployment had no tool to look this up at all, so every "no approved mapping" answer was a hardcoded default that happened to be right, not a real check — caught during live testing (`plan.md`). Fixed with `LINE_ITEM_MAP_SV` + a `line_item_map_lookup` tool, made the mandatory first step of every Stage 2 flow. If you're implementing this check anywhere else, verify it against a case where the check should fail *and* a case where it should pass — not just one where a hardcoded default happens to look correct.
- **`PRAMAN.CORE.RULE_CORPUS_SEARCH`** — the rule paragraph each line item's `RULE_CHUNK_ID` points to, for the citation on each finding.
- **`PRAMAN.CORE.CREDIT_EXPOSURE_SV`** — computing the actual value for a line item per its `TRANSFORM_LOGIC` (2a); row-level `entry_id`/`account_code`/`amount`/`position_id` for sign/duplicate/referential checks (2b); `counterparty_account_baseline_mean`/`_stddev`/`_count` for the per-counterparty scale check (2b) — compute `ABS((entry_amount - mean) / NULLIF(stddev, 0))` yourself, these are window metrics, not a pre-named z-score metric.
- **`PRAMAN.CORE.GL_OUTLIER_SIGNALS`** — pre-computed monthly outlier flags per `ACCOUNT_CODE`, the shared detector.
- **`PRAMAN.CORE.DIVERGENCE_DISCLOSURES`** — real bank-reported-vs-RBI-assessed pairs; useful as calibration context for how large a divergence has historically triggered regulatory action (not a live check against the draft return itself — this table is Stage 2's *eval* ground truth, not a runtime input for a specific bank's filing).

## Workflow

1. **For each line item in the draft return (2a)**, look up its `LINE_ITEM_MAP` row. If none exists, or the existing row is `proposed`, that itself is a finding ("no approved mapping for this line item" / "mapping pending governance approval") — don't compute a value against an unapproved rule.
2. **Compute the expected value** from `TRANSFORM_LOGIC` via the relevant Semantic View, and compare against the draft return's stated value.
3. **Run ledger-integrity checks (2b) regardless of any line item's approval status** — sign (negative amount on an account type that shouldn't be), duplicate posting (same counterparty+position+account_code+amount, not date — a real duplicate commonly lands on a different date), referential integrity (`GL_ENTRIES.POSITION_ID` pointing at a nonexistent `POSITIONS` row), and per-counterparty scale anomaly (`counterparty_account_baseline_count >= 3 AND |z| >= 3`).
4. **A qualifying scale anomaly is not on its own evidence of a defect.** Check `COUNTERPARTIES.CONCENTRATION_GROUP` before calling it a likely error — a counterparty already `LARGE_EXPOSURE_TOP5PCT` being large is corroborating evidence of legitimacy. Only call it a likely error if a *different* check also fails for that entry, or the counterparty isn't in a large-exposure group and still shows an extreme deviation.
5. **Check `GL_OUTLIER_SIGNALS`** for the line item's underlying `ACCOUNT_CODE` — a value mismatch AND a flagged outlier month is a higher-severity finding than a mismatch alone.
6. **Retrieve the rule paragraph** (`RULE_CHUNK_ID`) for each 2a finding's citation.
7. **Rank findings** by severity: a value mismatch with a corroborating outlier flag ranks above a mismatch alone, which ranks above a stylistic/completeness note. Genuinely uncertain findings get **abstained**, not forced into a confident direction — `architecture.md`'s Evaluation architecture treats abstention as a first-class outcome, confirmed live in eval (`eval/results.md`: `correct_but_anomalous` correctly resolves to `abstained`, not a forced verdict).
8. **Write the `AUDIT_LOG` row.**

## Output shape

Ranked findings list, one entry per finding:
- `LINE_ITEM_ID` or entry/account reference, draft value vs. computed value (or "no approved mapping" / the specific integrity issue, if that's the finding)
- Citation: **rule paragraph OR data lineage, per finding** (`architecture.md`'s stage table — not always the same citation type across findings in one run)
- Severity and confidence (including `abstained` as a valid state)
- Supporting signal, if any (`GL_OUTLIER_SIGNALS` flag, `CONCENTRATION_GROUP` corroboration)

## Audit logging

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, RETRIEVED_RULE_CHUNK_IDS, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (<uuid>, <analyst username>, '2', <the draft return identifier>, <model version>,
   ARRAY_CONSTRUCT(<every CHUNK_ID cited across all findings>), <the ranked findings list>,
   NULL, FALSE);
```

`HUMAN_DECISION` and `SIGNOFF_BY`/`SIGNOFF_AT` are set by the officer's actual sign-off action — a separate `AUDIT_LOG` insert via `SP_RECORD_SIGNOFF` under the `OFFICER_SIGNOFF` role (`sql/procedures/02_sp_record_signoff.sql`), linked back to this run via `SIGNOFF_FOR_RUN_ID`. A sign-off is always a new row, never an `UPDATE` of this one.

## Common mistakes

- **Validating against a `proposed` `LINE_ITEM_MAP` row as if it were approved.** This is the single most important guardrail in this skill — check `STATUS` every time, don't cache an assumption that a mapping is approved from an earlier run.
- **Gating basic ledger-integrity checks (2b) behind `LINE_ITEM_MAP` approval.** A raw-data sanity check isn't "computing an approved line item's value" — a real eval miss found this over-application blocking sign/scale/duplicate checks that should always run regardless of approval status.
- **Collapsing "no approved mapping exists yet" into a false negative.** That's a distinct, nameable finding ("mapping pending governance approval"), not silence and not a clean bill of health.
- **Calling a legitimately large entry a defect without checking `CONCENTRATION_GROUP` first.** A real, previously-measured false positive (`eval/results.md`'s `correct_but_anomalous` case).
- **Re-implementing outlier scoring inline** instead of querying `GL_OUTLIER_SIGNALS` — this is exactly the drift "one detector, two consumers" exists to prevent.
- **One verdict for the whole return.** Every line item/entry is its own finding with its own citation and severity; don't compress a multi-finding review into a single pass/fail sentence.
