# Stage 1 slice — `circular-interpret` run against RBI/DoS/2026-27/415

Manually executed run of `skills/circular-interpret.SKILL.md`'s workflow against the one circular already ingested into `RULE_CORPUS` (all 30 chunks of `RBI/DoS/2026-27/415`, the Supervisory Returns Directions) and the 9 `LINE_ITEM_MAP` rows seeded in `sql/seed_line_item_map.sql`. This is the "Stage 1 slice" from `plan.md`'s Days 12–15 — a real, evidence-grounded gap analysis, change spec, and test cases, not a synthetic example. No live agent call was made for this; the analysis itself doesn't need one (it's retrieval + comparison over data already local), but a real `AUDIT_LOG` row for this run is at the bottom.

## Method

Went through all 30 numbered paragraphs of the circular (`data/processed/rule_corpus_chunks.csv`), classified each as a data/reporting requirement or not, and checked whether an existing `LINE_ITEM_MAP` row already cites it. Per the skill's own escalation rule, ambiguous cases are flagged, not resolved confidently.

## Gap analysis

**What the circular actually establishes**, by section:

| Section | Paras | What it imposes |
|---|---|---|
| Ch. I, Preliminary | 1–5 | Scope/definitions — no data requirement |
| Ch. II, Governance and Oversight | 6–17 | **Process/control obligations**: data-quality risk management (6), validation practices (7), consolidated reporting capability (8), M&A due diligence impact on reporting (9), data architecture/IT infrastructure (10–13), reconciliation and record-keeping (14–15), automation (16), accuracy monitoring (17) |
| Ch. III.A, Operational Guidelines | 18–20 | Filing mechanics (online portals, maker/checker access), domestic + overseas (IBU/OBU) reporting scope |
| Ch. III.B, List of Applicable Returns | **21** | **The only paragraph that names which return contains which data** — ~30+ distinct returns, each with a periodicity, reference date, and one-line content description |
| Ch. III.C–F | 22–26 | Filing timelines per periodicity (22), timeline exceptions for 12 specific returns (23), penalties for non-compliance (24), ad-hoc/additional returns (25), non-interference with other regulatory returns (26) |
| Ch. IV, Repeal | 27–30 | Repeals prior instructions, preserves prior actions/approvals, doesn't override other laws, RBI's interpretation is final |

**Against the 9 seeded `LINE_ITEM_MAP` rows** (`PILLAR3.IND_EXPOSURE.FUND/NONFUND`, `PILLAR3.IND_NPA.GROSS/PROVISIONS`, `PILLAR3.NPA_CLASS.*` — all citing para 21):

- **No change needed.** Para 21's description of RAQ ("asset classification and provisioning for the advances and investment portfolio... sector-wise granular break up of credit and investment portfolio") is unchanged from what the seed script already cited. This circular doesn't redefine NPA classification or exposure calculation rules — it only confirms which return carries this class of data. The existing citation holds.
- **Real, honest coverage gap: everything else in para 21.** The 9 seeded rows cover the RAQ/RCA-III slice of one table in one paragraph. Roughly two dozen *other* named returns in the same table (ALE, ROR, RBS, Liquidity Return, IRS, RLC, CRILC, RFA, RDB, ROC, RoS, CPR, BSA, ALO, RLE, CEM, ROP, RCE, LRR, LEF, BLR, FINCON, FSI, GML, FMR-SCBs and its variants, VMR-I/II, plus several more without clean abbreviations in the source text) have **zero** `LINE_ITEM_MAP` coverage — expected, since the synthetic data generator only reconciles to HDFC's disclosed Pillar 3 figures (`generator/anchors.py`), not these other returns' specific fields. Flagging this explicitly rather than treating "we cite para 21" as if it meant "this circular is covered" — it means one row of one table in it is.
- **New requirement category this circular introduces that `LINE_ITEM_MAP`'s schema can't express — flagged for escalation, not resolved:** paragraphs 22–24 establish per-return filing *deadlines* and *penalties for missing them* (e.g. "RAQ monthly section: within 15 days," "RCA-III quarterly: within 21 days," 12 returns with bespoke exception timelines). This is a genuinely different kind of governed fact than `LINE_ITEM_MAP` models — `SOURCE_TABLE`/`SOURCE_COLUMN`/`TRANSFORM_LOGIC` describes a data aggregation rule, not a deadline-compliance rule. Per the skill's instruction ("genuine ambiguity gets flagged for escalation, not resolved confidently"), this is not proposed as a bolted-on `LINE_ITEM_MAP` row — it would need either a schema extension or a separate governed table, and that's a design decision for a human, not something to force through this slice.
- **Chapter II's governance/control obligations (paras 6–17) are out of `LINE_ITEM_MAP`'s scope entirely**, and correctly so — they're firm-level controls (data architecture, validation staffing, reconciliation discipline), not report line items. No finding needed here; noting it so a reader doesn't wonder why 12 paragraphs produced zero proposed rows.

## Change spec

**No `LINE_ITEM_MAP` rows added or modified.** The one finding this circular produces against our current 9 rows is "citation confirmed, unchanged" — not a change. Proposing new rows for the ~two-dozen uncovered returns would require synthetic data reconciled to *those* returns' specific figures, which doesn't exist yet (out of scope for this slice — a real gap for future data-sourcing work, tracked here rather than silently ignored).

## Test cases

| # | Input | Expected | Why |
|---|---|---|---|
| 1 | `SELECT RULE_CHUNK_ID FROM LINE_ITEM_MAP WHERE LINE_ITEM_ID LIKE 'PILLAR3.%'` | All 9 rows return `RBI/DoS/2026-27/415#21` | Citation should be stable across this circular version — nothing in it changes the RAQ/RCA-III description |
| 2 | Query `RULE_CORPUS_SEARCH` for "asset classification and provisioning" | Top result is chunk `#21` | Confirms the seeded citation is actually the best-retrievable match, not just asserted |
| 3 | Ask `assure-return` to validate `PILLAR3.IND_NPA.GROSS` today | Returns "no approved mapping / pending governance approval" | All 9 rows are still `STATUS='proposed'` — this is the same check already verified live in `SIGNAL_ASSURE_AGENT`'s Days 9–12 testing, included here for completeness of the Stage 1→2 handoff |
| 4 | Ask `circular-interpret` "does circular 415 define how NPA is classified" | Should answer "no — it names RAQ as the return that contains this data, not the classification methodology itself" | Tests that the skill doesn't overstate what para 21 actually establishes, matching the caveat already written into `sql/seed_line_item_map.sql` |

## Audit log entry for this run

```sql
INSERT INTO PRAMAN.CORE.AUDIT_LOG
  (RUN_ID, APP_USER, STAGE, PROMPT_OR_QUESTION, MODEL_VERSION, RETRIEVED_RULE_CHUNK_IDS, OUTPUT, HUMAN_DECISION, IS_EVAL)
VALUES
  (UUID_STRING(), CURRENT_USER(), '1', 'Stage 1 slice: gap analysis of RBI/DoS/2026-27/415 against seeded LINE_ITEM_MAP',
   'manual-analysis-v1',
   ARRAY_CONSTRUCT('RBI/DoS/2026-27/415#21', 'RBI/DoS/2026-27/415#22', 'RBI/DoS/2026-27/415#23'),
   'See demos/stage1_circular_415_gap_analysis.md -- no LINE_ITEM_MAP changes proposed; flagged the filing-timeline/penalty requirement category as needing a schema decision before it can be modeled.',
   NULL, FALSE);
```

Not yet run — add to `NOTES.md` if you want this logged for real.
