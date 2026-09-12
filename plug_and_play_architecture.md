# Plug-and-play architecture — design, not yet built

Prompted by: could Praman deploy against a real bank's own Snowflake account with minimal setup, rather than as a one-off prototype? This doc designs the architecture that would make that true. Two simplifying assumptions set the scope, both explicit product decisions, not gaps:

1. **The bank loads its data into Praman's canonical schema — natively or via its own adaptor.** Praman does not build per-institution ETL from arbitrary core-banking systems (Finacle, Temenos, mainframes). That's each institution's own integration work, bounded by a documented contract (below), the same way any data product draws a line between "our schema" and "your ETL."
2. **Detector thresholds are calibrated by a pipeline, not hand-picked constants.**

With these two assumptions, the picture that emerged from `production_deployment_analysis.md` changes substantially — for the better. That doc's crux finding (`LINE_ITEM_MAP.TRANSFORM_LOGIC` is descriptive, not executable, so onboarding meant hand-writing new Semantic View SQL) was solving the wrong-sized problem: it assumed every institution has its *own* schema forever. If every institution instead conforms to *one* canonical schema, the Semantic Views, `LINE_ITEM_MAP` mechanism, agent, and skills don't need to regenerate per institution at all — they need to regenerate per **jurisdiction**, which changes far less often and is already substantially portable (`jurisdiction_agnostic_analysis.md`).

**Revision 1, same day — the first draft had a hole, found by asking a concrete cross-domain example.** "Canonical schema is fixed, only content varies per jurisdiction" quietly assumed every regulator wants the *same kind* of data — bank credit/exposure/NPA, a Basel-Pillar-3-shaped world. That's not true. A securities market regulator (Japan's JPX/JFSA was the concrete case that surfaced this) asking for trade records between specific stock codes over a date range isn't a banking-book question at all — there is no `TRADES` table, no `STOCK_CODE`, no execution timestamp anywhere in `PRAMAN.CORE`, and no `LINE_ITEM_MAP` row could ever satisfy that requirement no matter how it's worded, because the underlying data was never modeled. This is a **schema coverage gap**, not a content-mapping gap, and it doesn't shrink under the canonical-schema assumption. §0 below is the fix: a coverage check that runs *before* assuming "just reseed content," and §5 addresses the second gap the same example exposed — this project has never built a real data-collection pipeline, only a one-time synthetic generator and a batch load.

**Revision 2, same day — an independent review cross-checked every claim against the actual SQL (`sql/detectors/`, `sql/rbac/`, `sql/ddl/`) and found nine real design gaps, resolved below rather than just catalogued.** The headline: this design never considered **Snowflake Native Apps** as an alternative to "reseed scripts into each customer's account." Native Apps exist specifically to solve the problem the original distribution model had no answer for — how a bug fix reaches a bank that already onboarded. Confirmed via the bundled `native-app-provider` skill: application packages support real versioning, patches, release channels, and an explicit "upgrade consumers" action (`SHOW VERSIONS IN APPLICATION PACKAGE`, `app-version-release/SKILL.md`) — none of which "run `sql/ddl/*.sql` again by hand" has ever had an equivalent for. This is `[FIX #1]` below, and it changes how every other section is read: the "fixed core" is now a versioned package, not a one-off script run.

## [FIX #1] Distribution model — decided, with named open questions

**Two paths, genuine tradeoffs:**

- **A. Hand-rolled per-account install (the original, implicit choice).** Praman's team runs the DDL/RBAC/seed scripts into the customer's account directly. Full control per account, but every bug fix to `SIGNAL_ASSURE_AGENT`'s instructions, every skill correction, every schema patch has to be manually re-run against every already-onboarded customer, by hand, with no built-in versioning of "which fix has this customer received." Does not scale past a handful of institutions and has no update story at all.
- **B. Snowflake Native App (application package).** Package the fixed core — schema DDL, RBAC roles, detector views/UDF, the four Semantic Views, `SIGNAL_ASSURE_AGENT`, and the four skills — as a versioned application package. The bank installs it into their own account (data never leaves their account, satisfying the same residency requirement the current design already relies on). Upgrades ship as new package versions the consumer pulls — a real Snowflake mechanism, not something Praman has to build.

**Decision: adopt B as the target, keep A only as a manual bridge until B is built.** `native-app-provider`'s manifest/setup-script/versioning model maps directly onto the "fixed core" box below. This doesn't change §§1–4's boundaries (data adaptor, regulatory content, calibration, circular parser stay per-institution/per-jurisdiction concerns *outside* the package) — it changes how the *inside* of the fixed-core box gets delivered and updated.

**Two real open questions this decision doesn't resolve, named rather than hand-waved — the actual content of a scoped, time-boxed spike before committing further build effort:**
1. A Native App's setup script runs with restricted privileges relative to a hand-run DDL script — the RBAC grants in `sql/rbac/` need re-verification under the app framework's grant model, not an assumption they port unchanged.
2. The bank's own `GOVERNANCE_WRITE`-approved `LINE_ITEM_MAP` rows are customer data living *inside* the installed app's schema, not shipped with the package — package upgrades must not touch that table's contents, only its DDL if a jurisdiction-driven column changes ([FIX #2]). Relatedly: can a Semantic View built against a consumer's own table actually work inside the Native App References/Restricted Caller Rights security model at all (not confirmed, needs the spike), and where does `AUDIT_LOG` live — inside the app's schema or the consumer's, referenced back — given examiners need to inspect audit data independent of whether the app itself is later upgraded or removed.

If the spike confirms these, §§1–5 below ship as a Native App from the start; if Semantic Views turn out unsupported inside the References model, the hand-rolled path (A) proceeds as designed, now ruled out on evidence rather than never considered.

## The core principle, revised for [FIX #1]

**Fixed core — now a versioned package, not a one-off script run — plus four explicit adaptor boundaries, gated by a domain check that runs first:**

```
                    ┌───────────────────────────────────┐
                    │  §0. DOMAIN COVERAGE CHECK          │
                    │  (per new regulator, run first,     │
                    │   against a written checklist)      │
                    │  same domain → proceed below        │
                    │  new domain  → extend the core       │
                    │                 itself (§0's note)   │
                    └──────────────────┬──────────────────┘
                                       │ same domain
                                       ▼
┌─────────────────────────────────────────────────────────────┐
│  FIXED CORE — packaged as a versioned Snowflake Native App    │
│  (FIX #1). Installed once per customer account; upgrades      │
│  ship as new package versions, not re-run scripts.            │
│                                                                 │
│  Canonical schema (PRAMAN.CORE, base + jurisdiction           │
│  extension columns — FIX #2) · RBAC (sql/rbac/) ·              │
│  Detector formulas (ZSCORE UDF) · SIGNAL_ASSURE_AGENT ·        │
│  Skills (skills/) · Audit design (AUDIT_LOG, sign-off)         │
└─────────────────────────────────────────────────────────────┘
        ▲                ▲                  ▲                ▲
        │                │                  │                │
┌───────┴──────┐ ┌───────┴───────┐ ┌────────┴────────┐ ┌─────┴─────┐
│ 1. Data      │ │ 2. Regulatory │ │ 3. Threshold    │ │ 4. Circular│
│   adaptor    │ │   content     │ │   calibration   │ │   parser   │
│ (per         │ │ (per          │ │   pipeline      │ │ (per       │
│  institution)│ │  jurisdiction)│ │ (per institution)│ │  jurisdiction)│
└──────┬───────┘ └───────────────┘ └─────────────────┘ └────────────┘
       │ feeds from
       ▼
┌─────────────────────────────────────────────────────────────┐
│  §5. DATA COLLECTION PIPELINE (does not exist yet — target     │
│  shape defined by §1; must also detect/handle late             │
│  corrections and restatements landing after signals were       │
│  already computed, FIX #7)                                     │
└─────────────────────────────────────────────────────────────┘
```

Everything in the fixed core is exactly what's already built and verified this session (12/12 eval, 22/22 RBAC, the sign-off fix) — **but only within the regulatory domain that core already encodes: bank credit risk, exposure, and asset-quality reporting.** The plug-and-play work is the distribution decision above, formalizing the four boundaries below, building the one genuinely new piece inside them (calibration), and checking §0 before assuming the boundaries even apply.

## 0. Domain coverage check — a checklist, not an unenforced judgment call

Before treating "add a jurisdiction" as an adaptor-and-reseed problem, answer one question: **does this regulator's requirement live inside the domain `PRAMAN.CORE` already models, or a different one?**

- **Same domain (credit risk / exposure / asset quality)** — RBI, and plausibly other bank prudential regulators with a similar Basel-derived shape (MAS, APRA, HKMA, per the original Markets section's list, and confirmed for six real markets — see Research Findings below). §§1–4 apply as designed: adaptor + reseeded content, schema *extension* possible ([FIX #2]) but no new domain.
- **Different domain** — a securities market conduct/surveillance regulator (JPX/JFSA asking for trade records between stock codes over a date period is the concrete case that exposed this), a payments-settlement regulator, an insurance-underwriting regulator. **The canonical schema itself needs a new domain schema** (e.g. a `TRADES` table: `STOCK_CODE`, `TRADE_DATE`, `EXECUTION_TIMESTAMP`, counterparty/broker identifiers, price, volume — modeled the same rigorous way `GL_ENTRIES`/`POSITIONS` were), its own detectors (market-conduct anomaly patterns are wash-trading/spoofing-shaped, not NPA-shaped), and very likely its own Semantic View, skill, **and Cortex Agent** — not a new tool bolted onto `SIGNAL_ASSURE_AGENT`. This is the same reasoning that drove the Stage 0+2 merge (`.claude/plans/lets-decide-what-would-rippling-lighthouse.md`), applied in the opposite direction: Stage 0 and Stage 2 share Semantic Views, detector views, and `ANALYST_READ`, so one agent avoided duplicating tool wiring for no isolation benefit. A market-conduct agent's tools, role, and Semantic Views have nothing in common with the credit-risk agent's — forcing them into one object would be the same mistake in reverse. A second regulatory domain is a real, product-level argument for a second `CREATE AGENT` object, not a reason to keep everything on one agent by default.

**This is not a smaller version of §§1–4 — it's a different-sized project each time it happens**, closer to "build a second product domain" than "onboard a new customer." Jurisdiction-agnostic within a domain is a real, verified property (`jurisdiction_agnostic_analysis.md`); domain-agnostic across regulatory subject matter is not something this architecture claims. The right scope statement is "one domain (bank credit/prudential reporting), jurisdiction-portable within it."

**`[FIX #3]` — this project already shipped exactly this failure mode once, and §0 as first written would have repeated it.** `SIGNAL_ASSURE_AGENT`'s original deployment had no tool to check `LINE_ITEM_MAP.STATUS` at all; its "no approved mapping" answers were a hardcoded default that happened to look right, not a real check, and it passed initial testing purely by accident (documented in `CLAUDE.md`). An unenforced §0 is the same shape of gap: a human is supposed to make the right call, with nothing checking that they did. Fixed the same way `LINE_ITEM_MAP` itself is governed — a real, recorded, gated row, plus a concrete checklist so the judgment is falsifiable rather than a vibe:

```sql
CREATE TABLE JURISDICTION_ONBOARDING (
  JURISDICTION              VARCHAR PRIMARY KEY,
  DOMAIN_COVERAGE_CONFIRMED BOOLEAN NOT NULL DEFAULT FALSE,
  CONFIRMED_BY              VARCHAR,
  CONFIRMED_AT              TIMESTAMP_NTZ,
  EVIDENCE                  VARCHAR   -- which specific schema elements were checked, not just a yes/no
);
```

The checklist that populates `EVIDENCE`, not a free-form judgment call:
1. Does the requirement reference an entity type already in the schema (`GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS`), even if it needs a new column? → same domain, go to [FIX #2]'s extension path.
2. Does it require a *new* entity type with no analog in the existing four tables (a trade record, a policy/premium record, a payment-instruction record)? → different domain, this section's "extend the core itself" branch.
3. Record the answer and the specific schema element checked against — so a later reviewer can verify the call was made against the actual schema, not asserted.

Content-pack seeding (§2) and the data-adaptor conformance check (`plug_and_play_build_plan.md` Phase 6) both check `DOMAIN_COVERAGE_CONFIRMED = TRUE` before proceeding, refusing to run against an unconfirmed jurisdiction the same way `assure-return` refuses to validate against an unapproved `LINE_ITEM_MAP` row. This doesn't make the *judgment* itself infallible — a human can still confirm wrongly — but it converts "did anyone check" from an assumption into an auditable fact, which is the actual lesson from the `LINE_ITEM_MAP` bug: the failure wasn't that a wrong call was made, it was that no mechanism could tell a checked answer from a default.

## 1. Data adaptor — per institution, contract-based, with the FX gap closed

**What changes:** nothing in the existing base schema. What's needed is a **formal, versioned contract** — "Canonical Banking Data Model v1" — documenting `PRAMAN.CORE`'s tables/columns/conventions as a stable target, not an incidental artifact of one synthetic firm:

- `GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS` column-by-column: types, nullability, meaning (already exists as DDL comments — needs consolidating into one canonical-schema reference doc). Evaluate the `dcm` skill's `DEFINE TABLE`/manifest model for this before writing it as a plain doc — real, diffable schema versioning across jurisdiction extensions, for free, rather than hand-consolidated comments.
- The `ACCOUNT_CODE` taxonomy enumerated explicitly as a closed (or extensible) vocabulary — `ADVANCES_FUND`/`ADVANCES_NONFUND`/`NPA_<classification>`/`NPA_PROVISION` — since every Semantic View, detector, and agent instruction depends on these exact strings (`jurisdiction_agnostic_analysis.md` already found this coupling; formalizing it as a documented contract turns "coupling" into "the adaptor's job").

**`[FIX #6]` Currency was wrongly called a cheap rename.** `jurisdiction_agnostic_analysis.md` treated parameterizing `CURRENCY` (dropping the hardcoded `DEFAULT 'INR'`) as rename-level. It isn't: `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS` aggregate `SUM(AMOUNT)` per counterparty/`ACCOUNT_CODE` with no currency dimension in the `GROUP BY` at all — a multi-currency book would silently sum unlike currencies into one z-score baseline, a correctness bug, not a formatting one. **Resolved as two explicit requirements:**
- **Schema-level:** `CURRENCY` becomes a real, non-defaulted column on `GL_ENTRIES`/`POSITIONS`/`TRANSACTIONS` — the adaptor sets it per row.
- **Detector-level, the actual fix:** `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS` add `CURRENCY` to their `GROUP BY`/window `PARTITION BY`, so a baseline is computed *within* a currency, never across currencies. An institution wanting one consolidated cross-currency baseline has to explicitly FX-normalize upstream in their own adaptor — same boundary as chart-of-accounts classification below, not something Praman's detector views silently do for them.

**What the bank owns:** getting real ledger/position/counterparty/transaction data into these tables in this shape — either natively or via their own adaptor (a dbt project, Dynamic Tables, a Snowpark pipeline — their choice, outside Praman's scope).

**Real remaining risk, stated precisely rather than glossed:** a bank's actual chart of accounts almost certainly doesn't map onto `ADVANCES_FUND`/`NPA_SUBSTANDARD`/etc. 1:1. Their adaptor has to *classify* their own accounts into this taxonomy — real analytical work on their side, not a mechanical column rename, and always needs a human who understands the institution's own chart of accounts.

## 2. Regulatory content — per jurisdiction, packaging mechanism unchanged

No architecture change from what `jurisdiction_agnostic_analysis.md` already found: `RULE_CORPUS` + `LINE_ITEM_MAP`'s governance *mechanism* (proposed→approved gate) are jurisdiction-agnostic today. Because every institution shares the same canonical schema, `LINE_ITEM_MAP` rows for a given jurisdiction are identical across every institution in it — a jurisdiction's rule corpus + line-item mappings are authored *once* and reseeded into every new customer's installed app (`sql/load_rule_corpus.sql`/`sql/seed_line_item_map.sql`, already built this way); each institution's `GOVERNANCE_WRITE` role independently approves its own copy in its own account.

**What changes:** package jurisdiction content (`RULE_CORPUS` seed + `LINE_ITEM_MAP` seed + agent orchestration's jurisdiction-specific instructions) as one versioned, reusable bundle per jurisdiction — mechanical repackaging of what's already built.

### `[FIX #2]` 2a. Canonical schema extension — the contradiction the first draft left unresolved

The first draft claimed the canonical schema is fixed *and* that every institution's Semantic Views/agent tools install "as-is." Research Findings (below) then documented that every real market studied (US, UK, EU, Singapore, Hong Kong, Australia) needed a genuine schema extension — EU forbearance, Hong Kong multi-entity consolidation, Australia counterparty tiering, Singapore/Hong Kong finer instrument-type categories. Those two claims can't both be true as stated. **Resolved with an explicit extension mechanism:**

- **The base canonical schema (the packaged core) is what's genuinely fixed and version-controlled** — the columns every jurisdiction studied so far actually shares.
- **Jurisdiction-specific dimensions are added as nullable extension columns on the existing tables** (e.g. `POSITIONS.FORBEARANCE_STATUS`, `COUNTERPARTIES.BUSINESS_SIZE_TIER`) — never as new standalone tables unless the concept genuinely doesn't attach to an existing row, and never a breaking change to a column already in use. `NULL` in a jurisdiction that doesn't need the dimension is the expected, common case.
- **Consequence for "installs as-is":** accurate for an institution in a jurisdiction whose dimension set the package already ships; **not** accurate for the first institution in a *new* jurisdiction needing a dimension the package doesn't yet have — that's a versioned package upgrade (new columns, corresponding Semantic View metric/dimension additions, corresponding agent tool description updates, [FIX #1]'s upgrade mechanism), shipped once per jurisdiction, not a bespoke per-institution fork.
- **Multi-entity consolidation (Hong Kong) is the one case that's a genuinely different shape, not a nullable column** — "roll up branch A + branch B + combined" is a query-time aggregation concern, not a row-level attribute. That needs a `REPORTING_ENTITY_HIERARCHY` table (parent/child entity relationships) and Semantic View changes to support rolling up by hierarchy level. Flagged explicitly so it doesn't get quietly waved through as "just a nullable column" during a future build.

This changes the priority order below: the schema-extension mechanism has to exist *before* a second jurisdiction can be onboarded at all, not just be "cheap to write" alongside other documentation.

**Still open:** a second jurisdiction needs its own circular parser (§4) and its own `ACCOUNT_CODE`-classification answer (map onto the existing taxonomy, or extend it per the mechanism above).

## 3. Threshold calibration pipeline — cold-start and versioning fixed

The real new piece. `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS`/`CREDIT_EXPOSURE_SV`'s scale-anomaly check all hardcode `|z| >= 3` and a minimum-baseline-period constant. These were picked against this project's synthetic data's specific volume and concentration — a real institution's transaction volume, counterparty concentration, and posting frequency will differ.

**`[FIX #5]` first, since it changes the table shape: no versioning/audit trail.** The original design stored one current-value row per dimension, overwritten each recalibration — a real defensibility problem for a regulator-facing tool: if the threshold moves from 3.0 to 2.7 next quarter, whether a transaction *would have* flagged last quarter becomes unanswerable. `AUDIT_LOG` is append-only by grant for exactly this reason; calibration needs the same discipline:

```sql
CREATE TABLE DETECTOR_CALIBRATION (
  CALIBRATION_ID       NUMBER AUTOINCREMENT,
  DETECTOR_NAME        VARCHAR,   -- 'TRANSACTION_SIGNALS' | 'GL_OUTLIER_SIGNALS' | 'CREDIT_EXPOSURE_SCALE'
  DIMENSION_KEY        VARCHAR,   -- e.g. ACCOUNT_CODE, or a channel/segment
  Z_THRESHOLD          FLOAT,
  MIN_BASELINE_PERIODS INT,
  IS_PROVISIONAL       BOOLEAN,   -- FIX #4
  EFFECTIVE_FROM       TIMESTAMP_NTZ NOT NULL,
  CALIBRATION_METHOD   VARCHAR    -- 'bootstrap_default' | 'percentile-95-historical' | 'manual-override'
);
```

No `UPDATE`/`DELETE` grant on this table, same as `AUDIT_LOG` — a new calibration is always a new row. Detector views join against the calibration row with the most recent `EFFECTIVE_FROM <= <the scored period>` for that dimension, not "the current row" — so re-running a *historical* period reproduces the threshold actually in force then, and a reviewer can see the full calibration history for any dimension.

**`[FIX #4]` cold start was silently assumed away.** `SP_CALIBRATE_DETECTOR_THRESHOLDS` needs historical data to compute a percentile threshold — a newly onboarded institution has none yet. Fixed with an explicit `IS_PROVISIONAL` flag: at onboarding, before enough history exists (the same minimum-baseline-periods logic the detectors already use), seed a row with the original hardcoded defaults (`Z_THRESHOLD = 3`, `MIN_BASELINE_PERIODS = 3`) and `CALIBRATION_METHOD = 'bootstrap_default'`, `IS_PROVISIONAL = TRUE`. `SP_CALIBRATE_DETECTOR_THRESHOLDS` inserts a real percentile-based row (`IS_PROVISIONAL = FALSE`) only once `MIN_BASELINE_PERIODS` worth of history actually accumulates. **Any signal produced while `IS_PROVISIONAL = TRUE` must be visibly flagged as such wherever it's surfaced** — to `SIGNAL_ASSURE_AGENT`'s consumers and to a reviewer — since an uncalibrated threshold is a materially different confidence level than a calibrated one, and hiding that distinction misrepresents signal quality.

Buildable now, independent of the other boundaries — pure SQL/procedure work against the existing detector views, doesn't require a real second institution to design (only to fully validate). Still the most self-contained piece if one gets built as a demo-strengthening artifact.

## 4. Circular/rule-document parser — per jurisdiction, real remaining engineering

Unchanged conclusion from `jurisdiction_agnostic_analysis.md`: `ingest/chunk_circular.py` is RBI-shaped (its `PREAMBLE_END_MARKERS`/`CHAPTER_RE`/`SUBSECTION_RE` assume RBI's exact document structure). The canonical-schema assumption doesn't shrink this problem — document structure varies by regulator regardless of how clean the downstream data model is.

**What changes, architecturally:** formalize the parser as a swappable adaptor with a fixed *output* contract (`RULE_CORPUS` row shape — already exactly what `chunk_circular.py` produces) and a documented but not-yet-fixed *input* contract. Two real implementation paths:
- **Structural (current approach's pattern, per regulator):** a new regex/structure-based parser module per jurisdiction, following `ingest/chunk_circular.py`'s "raise rather than silently mis-chunk" discipline. Verifiable, deterministic, brittle to format drift.
- **Semantic (LLM-based chunker):** prompt an LLM to identify citable paragraph units directly, regulator-agnostic. The bundled `ai-functions-pipeline-builder` skill's `blocks/ingest/parse-pages.md` (`AI_PARSE_DOCUMENT` with `page_split`, for page-level citation grain) is a real, pre-built implementation of this option, not a hypothetical — evaluate it directly against a real second-jurisdiction PDF before assuming a custom chunker needs to be written from scratch.

Not resolved here — worth a deliberate choice when a second jurisdiction's actual document is in hand.

## 5. Data collection pipeline — the piece that doesn't exist at all, restatement handling added

§1's data adaptor defines *where data has to end up*. It says nothing about *how it actually gets there on an ongoing basis*, and nothing in this project answers that today: `generator/generate_synthetic_data.py` (a one-time synthetic book) and `sql/load_synthetic_data.sql` (a one-time batch `COPY INTO`, re-run by hand) are the entire data story. No Dynamic Table, no Stream, no Task, nothing incremental, nothing near-real-time anywhere in this repo — a real, already-flagged gap (`plan.md` item 8, "data pipeline creation," a named CoCo-recommended task this project is at zero on). The JPX example is what makes it concrete beyond a checklist: GL entries post daily, trades happen continuously, and the track's own opening line asks for "real-time fraud, liquidity and credit risk" — a one-time load can never be the ingestion story for a live regulatory copilot.

**What a real pipeline layer needs, concretely:**

- **A staging → canonical transform, running on a schedule or trigger, not by hand.** Land the bank's adaptor output (§1) into a raw/staging table, then a Dynamic Table or a Stream+Task pair transforms it into `PRAMAN.CORE`'s canonical tables incrementally, replacing today's one-time `COPY INTO` entirely. The bundled `dynamic-tables` skill is exactly this mechanism, with a companion "apply recommendations" step for tuning refresh lag/warehouse sizing — use it directly rather than hand-rolling the DDL.
- **External reference-data collection**, for cases where the *regulator or exchange* — not the bank — is the source (a stock-code master list, a trading calendar). A scheduled Task/external function, or an Openflow connector, fetches and lands it as its own reference table — real, new infrastructure this project has never needed before.
- **Praman does not build bespoke connectors into arbitrary core-banking or trading systems** — same boundary §1 draws. It provides the native Snowflake ingestion *pattern*, not a one-time file drop repeated by hand forever.

**`[FIX #7]` restatements/backdated postings — a real gap, now resolved rather than left open.** `GL_OUTLIER_SIGNALS`' trailing baseline is a window function over `POSTING_DATE`. Real GL data gets corrected after the fact — a late-posted or restated entry backdated into an already-closed period retroactively changes that period's baseline, meaning a signal computed and possibly acted on last month could be wrong in hindsight, with no mechanism to detect that drift. **Two concrete additions, both preserving the same "never mutate history, append instead" discipline `AUDIT_LOG` already established:**
- **Detect it:** the incremental transform stamps every canonical row with `LOADED_AT` (when Praman actually ingested it), distinct from `POSTING_DATE` (the accounting period it belongs to). A row whose `POSTING_DATE` falls inside an already-signal-computed window but whose `LOADED_AT` is later than that computation is identifiable by a simple join — a restatement, not silently indistinguishable from an ordinary new row.
- **React to it:** signals computed from a window a later restatement touches get marked `SUPERSEDED_BY_RESTATEMENT` (a new nullable column on `GL_OUTLIER_SIGNALS`/`TRANSACTION_SIGNALS`, populated by a comparison job — never deleted or silently recomputed in place). A reviewer who already acted on the original signal has a visible trail that its basis was later superseded, rather than the number just changing under them with no record.

**`[FIX #8]` the external-access governance blocker — real, and sharper under the Native App model, not softer.** "A scheduled Task calling an external API, or an Openflow connector" reads like routine infrastructure. For a regulated bank, granting `CREATE EXTERNAL ACCESS INTEGRATION` and a `NETWORK RULE` for outbound calls is a security-team approval, often formal change control, not a config value Praman's deployment sets. Under [FIX #1]'s Native App model this gets *more* structured, not less: a Native App can only request external access the consumer explicitly grants at install/configuration time (a named EAI reference in the manifest, approved per installation via `native-app-provider`'s `request-external-access-integration` sub-skill) — meaning this isn't a one-time account-level negotiation, it's a per-customer approval baked into every install, with the manifest declaring exactly which external endpoints are needed up front. **State this explicitly in any onboarding-timeline estimate** — it's an organizational dependency with its own lead time, not something Praman controls the pace of.

## What does NOT change — precise, not overclaimed

Within the credit-risk/exposure domain (§0), and **for a jurisdiction whose dimension set the installed package version already supports** ([FIX #2]): `SIGNAL_ASSURE_AGENT`'s six tools, the four Semantic Views' SQL, the RBAC design, and the audit/sign-off design install as-is. The first institution in a jurisdiction needing a dimension the package doesn't yet ship triggers a versioned package upgrade ([FIX #1]) — a platform mechanism, not custom per-customer migration tooling.

## Research findings backing this design

Full cross-market research: `regulatory_landscape_research.md` (US/UK/EU, Singapore/Hong Kong/Australia, Japan banking + Japan securities-market-conduct, plus the current vendor/practitioner landscape).

**1. "Same domain" doesn't mean "zero schema change."** Every banking-prudential market researched (US, UK, EU, Singapore, Hong Kong, Australia) confirmed §0's same-domain judgment, and *every single one* still needed a real, bounded schema extension: the EU tracks forbearance as a dimension orthogonal to NPE status with no equivalent in `PRAMAN.CORE`; Australia's EFS collection requires counterparty business-size tiering finer than `COUNTERPARTIES.SECTOR`; Hong Kong requires multi-entity consolidation reporting with no equivalent concept in the schema at all (the exact case [FIX #2]'s `REPORTING_ENTITY_HIERARCHY` addresses); Singapore and Hong Kong both use instrument-type categories finer than the current `ADVANCES_FUND`/`ADVANCES_NONFUND` split. This is now formalized into a concrete extension mechanism ([FIX #2]) rather than left as an observation.

**2. Citation provenance/authority — found via Japan, not anticipated in the original four boundaries.** Japan's actual capital-adequacy notices are headed "(Provisional Translation)," with the Japanese original as the sole legally authoritative text (verified directly). Every finding is supposed to be citation-backed and defensible to an examiner, and "sourced from a non-authoritative provisional translation" fails that bar. `RULE_CORPUS` gains a provenance field (`SOURCE_AUTHORITY` + `ORIGINAL_LANGUAGE`), and any citation the agent surfaces from a non-authoritative source must carry that caveat in its actual output. RBI's circulars are English-original with no such layer, which is why this project never needed to think about it before. Verified for Japan; pattern-matched (not confirmed) for South Korea; China and EU member-state transpositions flagged as unverified leads.

**`[FIX #9]`** — provenance tagging alone doesn't verify retrieval actually works cross-lingually. Recording that a chunk is a translation doesn't confirm Cortex Search retrieves the *correct* chunk when an English question needs to surface a Japanese-original authoritative paragraph — cross-lingual embedding retrieval quality is a separate, empirical question the entire citation-backed premise depends on, and this design does not test it, only assumes it works. **Resolved as a required gate, not left open:** before treating a non-English-original jurisdiction as supported, run a retrieval spot-check — a set of known question→correct-chunk pairs in the query language, confirmed to actually retrieve the right `RULE_CORPUS` row above the relevance threshold the agent uses (same discipline as `eval/run_eval.md`). If retrieval quality is materially worse cross-lingually, the honest interim answer is a same-language-only constraint (query in the document's original language), not a silent accuracy regression presented as full support.

Also from that research: the competitive-differentiation claim holds up under scrutiny (no vendor found does Praman's specific NL-circular → cited-mapping → governance-gate → pre-filing-validation loop), and the AI-in-RegTech market is growing roughly twice as fast as RegTech overall (~37% CAGR).

## Priority order if this gets built

1. **[FIX #1] Distribution model spike** — resolve Native App vs. hand-rolled install (the two named open questions above) before investing further in per-institution scripts; this changes how every later step ships. `native-app-provider` skill.
2. **[FIX #3] Domain coverage check, now a checklist with a recorded gate (`JURISDICTION_ONBOARDING`)** — decision gate, not a build step, run and logged per candidate jurisdiction before scoping anything else.
3. **[FIX #2] Schema extension mechanism** — nullable-column convention + the one real exception (`REPORTING_ENTITY_HIERARCHY`). Blocks any second jurisdiction, not just "nice to formalize." Evaluate the `dcm` skill for versioning this. If #1 lands on Native Apps, this folds into the app manifest's own schema/version story.
4. **[FIXES #4, #5] Threshold calibration pipeline**, with the bootstrap-default cold-start path and append-only `DETECTOR_CALIBRATION`. Buildable independently, real SQL work, no second institution needed to build (only to fully validate).
5. **[FIX #6] Currency/FX correctness in the detector views**, alongside `ACCOUNT_CODE` parameterization — same "formalize the contract" work as #3, do together.
6. **[FIX #7] Minimal incremental pipeline with restatement handling from day one** (`dynamic-tables` skill) — not retrofitted later, since retrofitting `LOADED_AT`/`SUPERSEDED_BY_RESTATEMENT` onto a pipeline already in production is real migration work in its own right.
7. **Package jurisdiction content as an installable bundle** (§2) — mechanical repackaging.
8. **[FIX #9] Citation retrieval spot-check discipline** — required before claiming support for any non-English-original jurisdiction, not after.
9. **Circular parser generalization** (§4, `ai-functions-pipeline-builder` as a real candidate) — deferred until a second jurisdiction's real document is in hand.
10. **A second domain build** (§0's "different domain" branch) — only after a real candidate regulator forces the question; sized like a second product, not a checklist item.

None of this is required before the hackathon submission. It refines "is this possible" into something schedulable, ordered so the two items that actually *block* a second jurisdiction (distribution model, schema-extension mechanism) come before items previously treated as "cheap to do alongside" them. `[FIX #8]` (the external-access governance blocker) has no build step of its own — it's a per-institution lead-time dependency to plan around, not a task to schedule.

## Actors, content acquisition, and the literal build order

`plug_and_play_build_plan.md` goes one level deeper: who actually does each step (mostly existing roles — `GOVERNANCE_WRITE` already has `INSERT` on `RULE_CORPUS`, so content curation was already scoped into the RBAC design, never exercised), the concrete design for how new circulars actually get in (a governed discovery queue, not open scraping — official-source allow-list + a scheduled watcher + mandatory human review, with a manual-upload escalation path for exactly the CAPTCHA/login-gated cases `data-sources.md` already hit once for real), the translation/provenance gate this doc's Research Findings requires in practice, a phase-by-phase build sequence with flow diagrams, and which bundled Coco skills/plugins map onto which phase.
