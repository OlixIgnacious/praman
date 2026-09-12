# Can this deploy against a real institution's actual schema?

A component-by-component audit, prompted by the question: if a real bank adopted Praman tomorrow, would their actual core-banking/GL data just plug in? This is a **different axis from `jurisdiction_agnostic_analysis.md`** — that doc asks whether a new *regulator* requires new architecture; this one asks whether a new *institution's actual database*, even for the same regulator, requires new architecture. A second RBI-regulated bank's real ledger schema won't look like `PRAMAN.CORE` any more than a US bank's would. Every claim below traces to a real file, not a guess — same discipline as the jurisdiction doc: evidence first, verdict second.

The pitch already anticipates this is real work, not an oversight — `regulatory-reporting-problem-statement.md`'s Scope section lists "production connectors" under **explicitly roadmap**, and its Scalability section states outright: "the per-customer unit of work is the schema mapping — and that mapping compounds across customers... The accumulated regulation-to-data-field map is the asset, not the prompts." The question this doc actually answers is narrower and more useful than "is this deployable": **is that claim architecturally true today, or just the design intent?**

## ✅ Portable as-is, genuinely schema-agnostic

- **RBAC/governance/audit design** (`sql/rbac/`, `sql/ddl/09_audit_log.sql`) — four functional roles, maker-checker, append-only-by-grant logging. None of it references a table shape specific to this project; it would sit unchanged in front of any institution's data.
- **The Cortex Agent + CoWork orchestration *pattern*** — stage routing, the governance-gate-before-compute structure (Stage 2a/2b split), the `[EVAL]`-marker convention. The *shape* of the orchestration is reusable; only the specific tool/metric names it references are schema-coupled (see below).
- **`RULE_CORPUS` + Cortex Search** — rule text storage and retrieval has no dependency on what the ledger schema looks like at all (`ingest/chunk_circular.py`'s RBI-document coupling is a separate, already-documented issue — see the jurisdiction doc).
- **`LINE_ITEM_MAP`'s governance *mechanism*** (`sql/ddl/02_line_item_map.sql`) — `SOURCE_TABLE`/`SOURCE_COLUMN` columns, the proposed→approved gate, `VALID_FROM`/`VALID_TO` versioning. This is exactly the right abstraction for "a new institution's schema doesn't match" — a per-institution mapping table, not a shared one. Built as the integration seam from day one, not retrofitted.
- **The `ZSCORE`-based detector *pattern*** (`sql/detectors/01_zscore_udf.sql`) — mean/stddev/trailing-window anomaly scoring needs only an entity key, a date, and an amount column to work against. `sql/detectors/03_gl_outlier_signals.sql:19-20` groups by `ACCOUNT_CODE` and `GL_ENTRIES` generically — it doesn't hardcode which account codes matter, unlike the Semantic View below.

## 🟡 Would need real per-institution work, but of the kind the design expects

- **`TRANSACTIONS_SV`/`POSITIONS_SV`** (`sql/semantic_views/01_*.sql`, `02_*.sql`) — these reference this project's specific table/column names (`TRANSACTIONS.TXN_ID`/`AMOUNT`/`TXN_TIMESTAMP`, `POSITIONS.NOTIONAL`/`AS_OF_DATE`) but carry **no hardcoded business-classification logic** — no `CASE WHEN <specific code>` branching tied to a particular institution's conventions. Re-pointing these at a real institution's actual transaction/position tables is "write a new Semantic View against their columns," a bounded, mechanical adapter-view task — closer to a config change than a redesign.
- **`LINE_ITEM_MAP` rows themselves** — `SOURCE_TABLE`/`SOURCE_COLUMN`/`TRANSFORM_LOGIC` values are specific to `PRAMAN.CORE` today (e.g. `'GL_ENTRIES'`/`'AMOUNT'`, `sql/seed_line_item_map.sql:36`), but a new institution's rows would simply point at their own tables instead. Mechanically fine — *if* `TRANSFORM_LOGIC` were actually executed anywhere (see the crux finding below — it currently isn't).

## 🔴 The crux finding — the moat claim isn't architecturally true yet

**`LINE_ITEM_MAP.TRANSFORM_LOGIC` is descriptive text, not executable logic, and the real computation is duplicated as hand-written SQL elsewhere. Nothing keeps the two in sync.**

Concretely, `sql/seed_line_item_map.sql:37` stores this as a plain string, read by a human and cited by the agent, never parsed or run:

```
'SUM(AMOUNT) WHERE ACCOUNT_CODE = ''ADVANCES_FUND'' OR (ACCOUNT_CODE LIKE ''NPA\_%''...), JOIN COUNTERPARTIES ON ..., GROUP BY COUNTERPARTIES.SECTOR'
```

The *actual* logic that runs live is `sql/semantic_views/03_credit_exposure_sv.sql`'s `fund_based_exposure` metric (lines 99-104) — independently written SQL that happens to compute the same thing today, but is not generated from, validated against, or in any way mechanically linked to the `TRANSFORM_LOGIC` string above. Same story for `exposure_type`/`npa_classification` (lines 75-93, `CASE WHEN ACCOUNT_CODE = 'ADVANCES_FUND' ...`) and the three-way `ACCOUNT_CODE` string-literal coupling the jurisdiction doc already found in `sql/semantic_views/03_credit_exposure_sv.sql`, `sql/detectors/03_gl_outlier_signals.sql`, and `SIGNAL_ASSURE_AGENT.agent.yaml`.

**Practical consequence:** onboarding a second institution — even the same regulator, same jurisdiction, same report — is not "add new `LINE_ITEM_MAP` rows." It's:
1. Land the institution's real ledger data into Snowflake in some queryable shape (a real, often multi-month, data-engineering effort at most banks — entirely outside this repo, and usually the dominant cost of "onboarding," not the schema mapping itself).
2. Hand-write new Semantic View SQL against their actual schema and business-classification conventions (not a `LINE_ITEM_MAP`-only change for `CREDIT_EXPOSURE_SV`'s regulatory-line-item logic specifically).
3. Update `SIGNAL_ASSURE_AGENT.agent.yaml`'s orchestration instructions, which reference today's exact metric names (`fund_based_exposure`, `gross_npa`, `entry_scale_zscore`'s underlying baseline columns, etc.).
4. Re-tune and re-validate detector thresholds (`|z| >= 3`, `>= 3` prior periods of baseline) against the new institution's actual transaction volume and counterparty concentration — these were never derived analytically, they were chosen against this project's synthetic data's specific shape, and a real institution's data almost certainly has a different one. This needs the same eval rigor `eval/run_eval.md` already established, not a copy-paste of the current thresholds.

None of this is a hidden flaw — `architecture.md`'s Build plan never claimed a metadata-driven query layer, and the Scope section's "production connectors" roadmap line already covers it. What this finding does is make precise *what* "production connectors" actually means here: making the Semantic View / detector layer **derive from `LINE_ITEM_MAP.TRANSFORM_LOGIC`** (dynamic SQL generation, or at minimum a build-time check that the two haven't drifted) rather than duplicating it by hand. Until that exists, "schema mapping is the moat, not a rewrite" describes the intended end state, not the current one.

## What would actually need to change, in priority order

Not done now — this is the checklist for when real-institution onboarding actually starts, ordered by what blocks what.

1. **Decide the integration strategy up front**: an ETL/adapter layer that normalizes each institution's real ledger into `PRAMAN.CORE`'s canonical shape (keeps every Semantic View/detector/agent instruction as-is, cost is a mapping layer per institution), versus a per-institution Semantic View rewrite (more work each time, no canonical-schema design burden). The adapter path is the one that actually makes the "schema mapping compounds across customers" pitch line true — recommend it, but it requires treating `PRAMAN.CORE`'s shape as a deliberately-designed canonical target, not (as it is today) a schema built to reconcile one specific HDFC disclosure.
2. **Land real ledger data into Snowflake** in whatever shape the chosen strategy needs. This is real data-engineering work, outside this repo's scope, and in most banks is the dominant cost of "onboarding" — worth being explicit about this in the pitch so "schema mapping" doesn't imply the hard part is already solved.
3. **Make `LINE_ITEM_MAP.TRANSFORM_LOGIC` executable**, or at minimum add a consistency check that it and the corresponding Semantic View metric agree — closing the "documented twice, linked never" gap this doc's crux finding identifies. This is the concrete engineering task standing between "prototype" and "second customer is new mapping rows, not new architecture."
4. **Re-tune detector thresholds against real data** — `|z| >= 3` and the minimum-baseline-period constants were chosen against this project's synthetic data, not derived analytically; re-validate them the same way `eval/results.md` validated the agent's behavior, rather than assuming they transfer.
5. **Decide the `ACCOUNT_CODE`-equivalent convention question per institution** — same fork already identified in `jurisdiction_agnostic_analysis.md` item 3, but now per-institution rather than per-jurisdiction: does a new customer's classification scheme map onto this project's existing convention, or does onboarding also mean extending the three hardcoded consumers.

## The honest verdict

**Not deployable as a drop-in against a real institution's actual schema today — and the pitch already says so via the "production connectors" roadmap line.** What's genuinely built and portable: the governance/audit/RBAC design, the agent orchestration pattern, the rule-ingestion-and-citation pipeline, and — most importantly — `LINE_ITEM_MAP` as the *right conceptual seam* for per-institution schema mapping. What's not yet true: that seam is not mechanically connected to the query layer that actually computes regulatory figures, so today "new institution" still means "new Semantic View SQL by hand," not "new `LINE_ITEM_MAP` rows." Closing that gap is real, well-scoped engineering — not a redesign, and not something this hackathon's scope ever claimed to have solved.
