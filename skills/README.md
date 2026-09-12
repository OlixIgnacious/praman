# Praman skills — portability, read before installing elsewhere

Four real, loadable Coco skills, one per stage of Praman's regulatory-reporting lifecycle. Verified locally (`cortex skill add ./skills/<name>`, confirmed via `cortex skill list`) and installable by anyone directly from this GitHub repo (`cortex skill add OlixIgnacious/praman`).

## What "reusable" actually means here — read this before installing against a different account

**These skills will not work unmodified against a different Snowflake account or a different bank's schema, and you should not expect them to.** Every workflow references concrete objects that exist only in this project's `PRAMAN.CORE` schema — `TRANSACTIONS_SV`, `CREDIT_EXPOSURE_SV`, `LINE_ITEM_MAP`, `ACCOUNT_CODE` string conventions like `'ADVANCES_FUND'`, specific RBI circular citations. If you install these skills into an unrelated Snowflake account, they will still *activate* — the trigger descriptions are intentionally generic risk/compliance vocabulary ("signal", "flag", "concentration limit", "assure this return") — and then fail, querying tables that don't exist in your account. That's a real limitation, not a caveat to gloss over: see `production_deployment_analysis.md`'s crux finding, which is exactly this problem at the data-model level (line-item mappings are documented, not executable/parameterized).

**What genuinely transfers, and is worth forking for:**
- The **governance discipline**: never validate against an unapproved mapping, never present a statistical outlier as a confirmed defect, always abstain rather than force a confident-but-wrong verdict.
- The **Stage 2a/2b split pattern**: separate "compute a governed value" (needs approval) from "basic data-integrity sanity checks" (shouldn't need approval) — a real, eval-discovered design lesson (`eval/results.md`), not specific to RBI.
- The **citation discipline**: every finding cites something concrete (a rule paragraph, a data snapshot, a lineage trace) — never an unsupported assertion.
- The **audit-logging shape**: one `AUDIT_LOG` row per invocation, sign-off as a new row never an `UPDATE`, `IS_EVAL` isolation for held-out testing.

**How to actually reuse:** fork the skill directory, then replace every `PRAMAN.CORE.<object>` reference with your own schema's equivalent, and re-write the specific escalation/common-mistakes examples against your own data's actual failure modes — don't just point these files at a different account and expect correct behavior. This is a reference implementation of the pattern, not a drop-in tool.

## The four skills

- `signal-query/` (Stage 0) — live risk/fraud/liquidity signal queries, AML-adjacent flags routed to compliance, never auto-resolved
- `circular-interpret/` (Stage 1) — new-circular gap analysis against a governed line-item map, proposals only, never self-approving
- `assure-return/` (Stage 2) — pre-filing draft-return validation, ranked findings with citations, the governance-gate + integrity-check split
- `narrative-draft/` (Stage 3) — confirmed-finding root-cause tracing via native lineage, draft-only narrative output

Full design context: `architecture.md`'s "Per-stage component architecture" section.
