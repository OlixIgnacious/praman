# Pending manual runs

## Done

All of Days 9–12 and Days 12–15 — see `TRACKER.md`/`plan.md`. Stage 2's happy path is now genuinely demoed (not just the refusal path) after fixing a real bug: the agent had no tool to query `LINE_ITEM_MAP` at all, so every earlier "no approved mapping" result had been a hardcoded default, not an actual `STATUS` check. Fixed with a new `LINE_ITEM_MAP_SV` Semantic View + `line_item_map_lookup` tool, now the mandatory first step of every Stage 2 flow.

## One small thing pending — committing `LINE_ITEM_MAP_SV`'s DDL

`LINE_ITEM_MAP_SV` was created live in Snowflake but there's no matching source file in `sql/semantic_views/` yet — every other Semantic View in this repo has one. Run this and paste back the result:

```
cortex -c reg_reporting_agent "Run SELECT GET_DDL('SEMANTIC_VIEW', 'PRAMAN.CORE.LINE_ITEM_MAP_SV'); and show the full DDL text."
```

I'll turn that into `sql/semantic_views/04_line_item_map_sv.sql` and update `sql/semantic_views/README.md` to match, so the repo matches what's actually live.

## Next up

Days 15–17 — Eval: `INJECTED_CASES` catalogue, `EVAL_RESULTS`, evidence-pack export from `AUDIT_LOG`. Nothing else is currently pending your approval.
