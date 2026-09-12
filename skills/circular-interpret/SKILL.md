---
name: circular-interpret
description: "Interpret a new regulatory circular, Master Direction, or taxonomy version against a governed line-item map (LINE_ITEM_MAP), producing a gap analysis, change spec, and test cases -- human-approved before anything commits. Use when a new circular/taxonomy arrives and needs mapping onto report line items, or when asked what a specific rule paragraph changes or requires. Triggers: new circular, taxonomy update, gap analysis, change spec, what does this circular change, impacted line items, map this rule, RULE_CORPUS ingestion, does this regulation affect our reporting."
summary: Ingest a new circular or taxonomy version, map its requirements onto report line items, and produce a gap analysis, change spec, and test cases — human-approved before anything commits to the spine.
---

# Circular Interpret — Stage 1

## Overview

Stage 1 of the four-stage lifecycle. A new circular arrives; this skill's job is to say precisely what changed and which report line items it touches — not to silently update anything. Every output here is a **proposal**: `LINE_ITEM_MAP` rows this skill writes are `STATUS = 'proposed'`, and only a human `GOVERNANCE_WRITE` approval commits them (`sql/ddl/02_line_item_map.sql`'s column comment; `sql/seed_line_item_map.sql` follows the same discipline for the initial seed).

This is the one stage with an extra pipeline step the others don't have: a new circular isn't queryable until it's ingested. If it's already scraped text (see `ingest/README.md` — most RBI Master Directions are), run `ingest/chunk_circular.py` against it, then `sql/load_rule_corpus.sql`, before this skill can retrieve anything from it. If it's a raw PDF, `PARSE_DOCUMENT`/`AI_PARSE_DOCUMENT` runs first (`architecture.md`'s platform notes — Cortex Search does not parse PDFs itself). If the circular is from a different regulator than the one `ingest/chunk_circular.py` was built for, its `PREAMBLE_END_MARKERS`/`CHAPTER_RE`/`SUBSECTION_RE` assume a specific document structure — check `jurisdiction_agnostic_analysis.md` before assuming the existing parser applies unchanged.

## Data this skill reads and writes

- **Reads:** `PRAMAN.CORE.RULE_CORPUS_SEARCH` (the new circular's chunks, and the existing corpus for cross-reference), `PRAMAN.CORE.LINE_ITEM_MAP` (current mappings — including `proposed` rows still awaiting approval, so this skill doesn't propose a duplicate of something already pending).
- **Writes (as `GOVERNANCE_WRITE`'s proposal, not commit):** new `LINE_ITEM_MAP` rows, always `STATUS = 'proposed'`. This skill never sets `STATUS = 'approved'` itself — see `sql/seed_line_item_map.sql`'s own header comment on why a seeding/proposing step isn't the human governance step.

## Workflow

1. **Confirm ingestion.** The circular's chunks must already be in `RULE_CORPUS` (see Overview) before this skill can retrieve from it — check `RULE_CORPUS` for the `DOC_ID` first; don't retrieve against a document that isn't there yet.
2. **Retrieve the circular's own chunks** (filter by `DOC_ID`/`VERSION`) and read them in full — chunk grain is RBI's own numbered paragraph (`ingest/README.md`), so a chapter's worth of paragraphs is a handful of chunks, not one giant blob.
3. **Cross-reference against `LINE_ITEM_MAP`.** For each paragraph that imposes a data/reporting requirement, check whether an existing `LINE_ITEM_ID` already covers it (cite that `RULE_CHUNK_ID`) or whether this is new/changed ground.
4. **Classify each finding** as: *new requirement* (no existing line item), *changed requirement* (existing line item's `RULE_CHUNK_ID` is superseded — set `SUPERSEDES_CHUNK_ID` on the new `RULE_CORPUS` row if not already done at ingestion), or *no impact* (informational paragraph, no data requirement).
5. **Genuine ambiguity gets flagged for escalation, not resolved confidently** — per the problem statement's Stage 1 description. If a paragraph could plausibly map to two different line items, or its scope is unclear without cross-referencing a document not yet ingested (the `DoS.CO.PPG.66` taxonomy-delta gap in `data-sources.md` is a real example of this), say so explicitly rather than picking one.
6. **Produce the three outputs** (below), propose `LINE_ITEM_MAP` rows for anything new/changed, and write the `AUDIT_LOG` row.

## Output shape

- **Gap analysis** — which currently-approved line items this circular's requirements are NOT yet covered by (the actual gap), cited to the specific paragraph.
- **Change spec** — proposed new/updated `LINE_ITEM_MAP` rows (`LINE_ITEM_ID`, `SOURCE_TABLE`/`SOURCE_COLUMN`, `TRANSFORM_LOGIC`, `RULE_CHUNK_ID`), `STATUS = 'proposed'`.
- **Test cases** — concrete input/expected-output pairs a human reviewer (or a later eval run) could use to check the proposed mapping actually computes what the paragraph requires.

## Citation

Stage 1's citation type is **rule paragraph + version** (`architecture.md`'s stage table) — every finding cites a specific `CHUNK_ID`/`SECTION_REF`, never "the circular" as a whole. `sql/seed_line_item_map.sql`'s citations (all pointing at `RBI/DoS/2026-27/415#21`) are the worked example of how honest this citation should be: it says exactly what that paragraph does and doesn't establish, rather than overstating the fit.

## Audit logging

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, RETRIEVED_RULE_CHUNK_IDS, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (<uuid>, <analyst username>, '1', <trigger, e.g. the DOC_ID>, <model version>,
   ARRAY_CONSTRUCT(<every CHUNK_ID retrieved and cited>), <gap analysis + change spec + test cases>,
   NULL, FALSE);
```

`HUMAN_DECISION` is set later, by the governance approval step, not by this skill.

## Common mistakes

- **Proposing a `LINE_ITEM_MAP` row without a `RULE_CHUNK_ID`.** Every row needs a citation, even an imperfect one (flag the imperfection in `DESCRIPTION`, don't omit the citation).
- **Self-approving.** This skill proposes; it never sets `STATUS = 'approved'`, `APPROVED_BY`, or `APPROVED_AT`.
- **Treating the table of contents as content.** `ingest/chunk_circular.py` already strips the TOC before chunking — if a chunk looks like pure navigation, the ingestion step has a bug, not this skill.
