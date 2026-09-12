# Pending manual runs

Snowflake changes written but not yet executed — non-interactive `cortex exec` auto-denies mutating SQL, so these run in an interactive `cortex` session instead, where you approve each statement.

## Done

- Semantic Views, the shared detector, `SIGNAL_ASSURE_AGENT` (all Days 9–12 work), and the Stage 1/Stage 3 demo walkthroughs (`demos/`) — all deployed/complete. See `TRACKER.md`/`plan.md` for detail.

## Pending — one thing, to finish Stage 2's demo

Every seeded `LINE_ITEM_MAP` row is still `STATUS='proposed'`, so `SIGNAL_ASSURE_AGENT`'s Stage 2 tool has only ever been tested against the "no approved mapping" refusal path — the "compute value, compare to draft, ranked findings with a citation" happy path has never actually run. To demo that, approve at least one row as `GOVERNANCE_WRITE`, after reviewing the citation caveat already written into `sql/seed_line_item_map.sql` (all 9 rows cite `RBI/DoS/2026-27/415#21`, which names the return but not the underlying disclosure-format rule — an honest, not ideal, citation):

```sql
UPDATE PRAMAN.CORE.LINE_ITEM_MAP
SET STATUS = 'approved', APPROVED_BY = CURRENT_USER(), APPROVED_AT = CURRENT_TIMESTAMP()
WHERE LINE_ITEM_ID = 'PILLAR3.IND_NPA.GROSS';  -- or whichever row(s) you want to approve
```

Then a live question like *"Validate the gross NPA figure for [an industry] against approved rules"* against `SIGNAL_ASSURE_AGENT` in CoWork should show the full ranked-findings path instead of the refusal. Tell me the result and I'll close out Stage 2's checklist item.

## Also optional

`demos/stage1_circular_415_gap_analysis.md` includes a real `AUDIT_LOG` insert for that analysis run — not executed, since the analysis itself needed no live Snowflake access. Run it if you want that Stage 1 slice logged for real; otherwise it's fine as a standalone artifact.
