# Plug-and-play architecture — design, not yet built

Prompted by: could Praman deploy against a real bank's own Snowflake account with minimal setup, rather than as a one-off prototype? This doc designs the architecture that would make that true. Two simplifying assumptions set the scope, both explicit product decisions, not gaps:

1. **The bank loads its data into Praman's canonical schema — natively or via its own adaptor.** Praman does not build per-institution ETL from arbitrary core-banking systems (Finacle, Temenos, mainframes). That's each institution's own integration work, bounded by a documented contract (below), the same way any data product draws a line between "our schema" and "your ETL."
2. **Detector thresholds are calibrated by a pipeline, not hand-picked constants.**

With these two assumptions, the picture that emerged from `production_deployment_analysis.md` changes substantially — for the better. That doc's crux finding (`LINE_ITEM_MAP.TRANSFORM_LOGIC` is descriptive, not executable, so onboarding meant hand-writing new Semantic View SQL) was solving the wrong-sized problem: it assumed every institution has its *own* schema forever. If every institution instead conforms to *one* canonical schema, the Semantic Views, `LINE_ITEM_MAP` mechanism, agent, and skills don't need to regenerate per institution at all — they need to regenerate per **jurisdiction**, which changes far less often and is already substantially portable (`jurisdiction_agnostic_analysis.md`).

**Revision, same day — the first version of this doc had a hole, found by asking a concrete cross-domain example.** "Canonical schema is fixed, only content varies per jurisdiction" quietly assumed every regulator wants the *same kind* of data — bank credit/exposure/NPA, a Basel-Pillar-3-shaped world. That's not true. A securities market regulator (Japan's JPX/JFSA was the concrete case that surfaced this) asking for trade records between specific stock codes over a date range isn't a banking-book question at all — there is no `TRADES` table, no `STOCK_CODE`, no execution timestamp anywhere in `PRAMAN.CORE`, and no `LINE_ITEM_MAP` row could ever satisfy that requirement no matter how it's worded, because the underlying data was never modeled. This is a **schema coverage gap**, not a content-mapping gap, and it doesn't shrink under the canonical-schema assumption — it's a different problem the first draft didn't address. §0 below is the fix: a coverage check that runs *before* assuming "just reseed content," and §5 addresses the second gap the same example exposed — this project has never built a real data-collection pipeline, only a one-time synthetic generator and a batch load, and "plug and play" for live regulatory data can't mean either of those.

## The core principle

**Fixed core + four explicit adaptor boundaries**, one at every point real-world variance actually enters:

```
                    ┌───────────────────────────────────┐
                    │  §0. DOMAIN COVERAGE CHECK          │
                    │  (per new regulator, run first)     │
                    │  same domain → proceed below        │
                    │  new domain  → extend the core      │
                    │                 itself (§0's note)  │
                    └──────────────────┬──────────────────┘
                                       │ same domain
                                       ▼
┌─────────────────────────────────────────────────────────────┐
│  FIXED CORE (install once per customer account, unchanged    │
│  across every institution and every jurisdiction --          │
│  WITHIN the credit-risk/exposure/asset-quality domain)         │
│                                                                 │
│  Canonical schema (PRAMAN.CORE) · RBAC (sql/rbac/) ·           │
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
│  §5. DATA COLLECTION PIPELINE (does not exist yet --          │
│  see below. The adaptor defines the target shape; this is     │
│  the actual ingestion mechanism landing real, ongoing data     │
│  into it.)                                                     │
└─────────────────────────────────────────────────────────────┘
```

Everything in the fixed core is exactly what's already built and verified this session (12/12 eval, 22/22 RBAC, the sign-off fix) — **but only within the regulatory domain that core already encodes: bank credit risk, exposure, and asset-quality reporting.** The plug-and-play work is formalizing the four boundaries below, building the one genuinely new piece inside them (calibration), and — the part the first draft missed — checking §0 before assuming the boundaries even apply.

## 0. Domain coverage check — the step that has to run first, per regulator

Before treating "add a jurisdiction" as an adaptor-and-reseed problem, answer one question: **does this regulator's requirement live inside the domain `PRAMAN.CORE` already models, or a different one?**

- **Same domain (credit risk / exposure / asset quality)** — RBI, and plausibly other bank prudential regulators with a similar Basel-derived shape (MAS, APRA, HKMA, per the original Markets section's list). §§1–4 below apply as designed: adaptor + reseeded content, no schema change.
- **Different domain** — a securities market conduct/surveillance regulator (JPX/JFSA asking for trade records between stock codes over a date period is the concrete case that exposed this), a payments-settlement regulator, an insurance-underwriting regulator. **The canonical schema itself needs extension** — a new domain schema (e.g. a `TRADES` table: `STOCK_CODE`, `TRADE_DATE`, `EXECUTION_TIMESTAMP`, counterparty/broker identifiers, price, volume — modeled the same rigorous way `GL_ENTRIES`/`POSITIONS` were, not bolted onto the existing tables), its own detectors (market-conduct anomaly patterns are not credit-risk z-score patterns — think wash-trading/spoofing-shaped signals, not NPA-shaped ones), and very likely its own Semantic View and skill, parallel to the existing four rather than a fifth stage bolted onto Stage 0-3's credit-risk framing.

**This is not a smaller version of §§1–4 — it's a different-sized project each time it happens**, closer to "build a second product domain" than "onboard a new customer." Worth being honest about in the pitch: jurisdiction-agnostic within a domain is a real, verified property (`jurisdiction_agnostic_analysis.md`); domain-agnostic across regulatory subject matter (credit risk vs. market conduct vs. payments) is not something this architecture claims, and no amount of adaptor/reseed design changes that. The right scope statement is "one domain (bank credit/prudential reporting), jurisdiction-portable within it" — not "any regulator, anywhere."

## 1. Data adaptor — per institution, mostly assumed away, needs a contract

**What changes:** nothing in the existing schema. What's needed is a **formal, versioned contract** — "Canonical Banking Data Model v1" — documenting `PRAMAN.CORE`'s tables/columns/conventions as a stable target, not an incidental artifact of one synthetic firm. Concretely:

- `GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS` column-by-column: types, nullability, meaning (already exists as DDL comments — needs consolidating into one canonical-schema reference doc, not scattered across `sql/ddl/*.sql`'s individual header comments).
- The `ACCOUNT_CODE` taxonomy enumerated explicitly as a closed (or extensible) vocabulary — `ADVANCES_FUND`/`ADVANCES_NONFUND`/`NPA_<classification>`/`NPA_PROVISION` — since every Semantic View, detector, and agent instruction depends on these exact strings (`jurisdiction_agnostic_analysis.md` already found this coupling; formalizing it as a documented contract turns "coupling" into "the adaptor's job").
- `CURRENCY` handling: parameterized, not hardcoded `'INR'` (the cheap fix `jurisdiction_agnostic_analysis.md` already identified).

**What the bank owns:** getting their real ledger/position/counterparty/transaction data into these tables in this shape — either natively (if their existing warehouse is already close) or via their own adaptor (a dbt project, Dynamic Tables, a Snowpark pipeline — their choice, outside Praman's scope, same boundary every schema-first data product draws).

**Real remaining risk, worth stating precisely rather than glossing over:** a bank's actual chart of accounts almost certainly doesn't map onto `ADVANCES_FUND`/`NPA_SUBSTANDARD`/etc. 1:1. Their adaptor has to *classify* their own accounts into this taxonomy, which is real analytical work on their side, not a mechanical column rename. This is the one place "plug and play" is aspirational even after this design — the taxonomy classification step will always need a human who understands the institution's own chart of accounts.

## 2. Regulatory content — per jurisdiction, already substantially portable

No architecture change from what `jurisdiction_agnostic_analysis.md` already found: `RULE_CORPUS` + `LINE_ITEM_MAP`'s governance *mechanism* (proposed→approved gate) are jurisdiction-agnostic today. The new insight from the canonical-schema assumption: **because every institution shares the same schema, `LINE_ITEM_MAP` rows for a given jurisdiction are identical across every institution in it.** A jurisdiction's rule corpus + line-item mappings get authored *once* and reseeded into every new customer's account (`sql/load_rule_corpus.sql`/`sql/seed_line_item_map.sql`, already built this way) — each institution's `GOVERNANCE_WRITE` role independently approves its own copy in its own account, since "deploys into the customer's own Snowflake account" (an existing guardrail) means no cross-tenant sharing of live data is needed or wanted.

**What changes:** package jurisdiction content (`RULE_CORPUS` seed + `LINE_ITEM_MAP` seed + agent orchestration's jurisdiction-specific instructions, e.g. currency formatting) as one versioned, reusable bundle per jurisdiction — "the RBI/India content pack," installable into any new customer account via the existing seed scripts. Mechanical repackaging of what's already built, not new logic.

**Still open, unchanged from `jurisdiction_agnostic_analysis.md`:** a second jurisdiction needs `ingest/chunk_circular.py`-equivalent parsing for its own document format (see 4 below), and the `ACCOUNT_CODE` classification question (does the jurisdiction's Basel-derived NPA categories map onto the existing taxonomy, or does the canonical schema's taxonomy need extending).

## 3. Threshold calibration pipeline — genuinely new, per institution

The real new piece. `TRANSACTION_SIGNALS`/`GL_OUTLIER_SIGNALS`/`CREDIT_EXPOSURE_SV`'s scale-anomaly check all hardcode `|z| >= 3` and a minimum-baseline-period constant (`>= 3` periods/entries). These were picked against this project's synthetic data's specific volume and concentration — a real institution's transaction volume, counterparty concentration, and posting frequency will differ, and a fixed constant either over-flags (a high-volume bank) or under-flags (a low-volume one).

**Design:** a `DETECTOR_CALIBRATION` table (one row per institution/detector/dimension — e.g., per `ACCOUNT_CODE`, per signal type) holding the calibrated threshold, populated by a calibration procedure/Task rather than a hardcoded literal:

```sql
CREATE TABLE DETECTOR_CALIBRATION (
  DETECTOR_NAME       VARCHAR,   -- 'TRANSACTION_SIGNALS' | 'GL_OUTLIER_SIGNALS' | 'CREDIT_EXPOSURE_SCALE'
  DIMENSION_KEY       VARCHAR,   -- e.g. ACCOUNT_CODE, or a channel/segment
  Z_THRESHOLD         FLOAT,     -- calibrated, not hardcoded 3
  MIN_BASELINE_PERIODS INT,      -- calibrated, not hardcoded 3
  CALIBRATED_AT       TIMESTAMP_NTZ,
  CALIBRATION_METHOD  VARCHAR    -- e.g. 'percentile-95-historical', 'manual-override'
);
```

A `SP_CALIBRATE_DETECTOR_THRESHOLDS` procedure runs at onboarding (and re-runnable periodically, e.g. quarterly, as a Task) — computes each dimension's actual historical z-score distribution and sets the threshold to flag a defensible top-percentile (e.g., the value that would flag roughly the top 0.5–1% most anomalous periods historically), rather than assuming `3` is universally right. The detector views join against `DETECTOR_CALIBRATION` instead of a literal constant.

**This is buildable now, independent of the other three boundaries** — it's pure SQL/procedure work against the existing detector views, doesn't require a real second institution to design (only to fully validate). Reasonable next concrete step if you want to build one piece of this today.

## 4. Circular/rule-document parser — per jurisdiction, real remaining engineering

Unchanged conclusion from `jurisdiction_agnostic_analysis.md`: `ingest/chunk_circular.py` is RBI-shaped (its `PREAMBLE_END_MARKERS`/`CHAPTER_RE`/`SUBSECTION_RE` assume RBI's exact document structure). The canonical-schema assumption doesn't shrink this problem — document structure varies by regulator regardless of how clean the downstream data model is.

**What changes, architecturally:** formalize the parser as a swappable adaptor with a fixed *output* contract (`RULE_CORPUS` row shape: `CHUNK_ID`, `DOC_TITLE`, `SECTION_REF`, `CHUNK_TEXT`, etc. — already exactly what `chunk_circular.py` produces) and a documented but not-yet-fixed *input* contract. Two real implementation paths, a genuine design choice rather than a default:
- **Structural (current approach's pattern, per regulator):** a new regex/structure-based parser module per jurisdiction, following `ingest/chunk_circular.py`'s "raise rather than silently mis-chunk" discipline. Verifiable, deterministic, brittle to format drift.
- **Semantic (LLM-based chunker):** prompt an LLM to identify citable paragraph units directly, regulator-agnostic. More flexible, but fuzzier and harder to verify — a chunk boundary decision becomes a model judgment call instead of a checkable rule.

Not resolved here — worth a deliberate choice when a second jurisdiction's actual document is in hand (matching `jurisdiction_agnostic_analysis.md` item 1's existing advice not to guess a document's structure before seeing a real one).

## 5. Data collection pipeline — the piece that doesn't exist at all

§1's data adaptor defines *where data has to end up* (the canonical schema shape). It says nothing about *how it actually gets there on an ongoing basis*, and that's because nothing in this project answers that question today. The entire data story so far is two one-time operations: `generator/generate_synthetic_data.py` (a Python script inventing a synthetic book once) and `sql/load_synthetic_data.sql` (a batch `COPY INTO`, re-run by hand). There is no Dynamic Table, no Stream, no Task, nothing incremental, nothing scheduled, nothing near-real-time anywhere in this repo. This is a real, already-flagged gap (`plan.md` item 8's CoCo-lifecycle audit named "data pipeline creation" as an explicit recommended task this project is at zero on) — the JPX example is what makes concrete *why* it matters beyond a judging checklist: GL entries post daily, trades happen continuously, and the track's own opening line asks for "real-time fraud, liquidity and credit risk" — a one-time load can never be the ingestion story for a live regulatory copilot, regardless of how good the schema or the agent is.

**What a real pipeline layer needs, concretely:**

- **A staging → canonical transform, running on a schedule or trigger, not by hand.** Land the bank's adaptor output (§1) into a raw/staging table, then a Dynamic Table or a Stream+Task pair transforms it into `PRAMAN.CORE`'s canonical tables incrementally — replacing today's one-time `COPY INTO` entirely. This is genuinely buildable now, against the existing schema, independent of any specific institution's data.
- **External reference-data collection**, for cases where the *regulator or exchange* — not the bank — is the source. A stock-code master list or a trading calendar published by JPX isn't something the bank's adaptor produces; Praman would need to actually fetch it (a scheduled Task calling an external function/API, or an Openflow connector) and land it as its own reference table. This is real, new infrastructure this project has never needed before, because every existing data source (synthetic generator, scraped circulars) was either invented or one-time-fetched by hand.
- **Praman does not build bespoke connectors into arbitrary core-banking or trading systems** — same boundary §1 already draws. What it should provide is the native Snowflake ingestion *pattern* (the Dynamic Table/Task/Stream scaffolding, parameterized by target table) that a bank's own adaptor output, or a regulator's published reference data, plugs into incrementally — not a one-time file drop repeated by hand forever.

## What does NOT change

Worth stating explicitly, since it's most of the system, **within the credit-risk/exposure domain §0 checks for**: `SIGNAL_ASSURE_AGENT`'s six tools, all four Semantic Views' SQL, the RBAC design, the audit/sign-off design, and all four skills install into a new customer's account **as-is** — none of them need per-institution modification once the data adaptor (§1) and a real pipeline (§5) have landed real, ongoing data in the canonical shape. This is the actual payoff of the canonical-schema-first design within one domain: the fixed core is genuinely large, and the adaptor surface is genuinely small and well-bounded. It stops being true the moment a regulator's requirement falls outside that domain (§0) — that's a new-domain build, not an adaptor.

## Priority order if this gets built

0. **Domain coverage check (§0)** — not a build step, a decision gate. Run this for real against every candidate jurisdiction before scoping anything else; it determines whether §§1–5 apply at all or a new-domain build is needed instead.
1. **Formalize the canonical schema as a versioned contract** (mostly documentation — consolidate existing DDL comments into one reference doc). Cheap, unblocks everything else being precisely specified.
2. **Threshold calibration pipeline** (§3). Buildable independently, real SQL work, no second institution needed to build it (only to fully validate it).
3. **Currency + `ACCOUNT_CODE` parameterization** (`jurisdiction_agnostic_analysis.md`'s already-identified cheap fixes) — do alongside #1 since it's the same "formalize the contract" work.
4. **A minimal incremental pipeline (§5)**, even just a Dynamic Table replacing the one-time `COPY INTO` for the existing synthetic tables — the smallest real step toward "this handles ongoing, not one-time, data," and directly closes the CoCo-lifecycle "data pipeline creation" gap (`plan.md` item 8) at the same time.
5. **Package jurisdiction content as an installable bundle** (§2) — mechanical repackaging.
6. **Circular parser generalization** (§4) — genuinely deferred until a second jurisdiction's real document is in hand; don't build against a guess.
7. **A second domain build** (§0's "different domain" branch) — only after a real candidate regulator forces the question; sized like a second product, not a checklist item.

None of this is required before the hackathon submission. It's the answer to "is this possible" with enough precision to actually schedule, if pursued afterward — or to build one piece of (most naturally #2 or #4) as a demo-strengthening artifact if there's time before Days 17–18.

## Research findings, and two real design changes they force

Full cross-market research: `regulatory_landscape_research.md` (US/UK/EU, Singapore/Hong Kong/Australia, Japan banking + Japan securities-market-conduct, plus the current vendor/practitioner landscape). Two findings change this design, not just confirm it:

**1. "Same domain" doesn't mean "zero schema change" — soften §§1–4 accordingly.** Every banking-prudential market researched (US, UK, EU, Singapore, Hong Kong, Australia) confirmed §0's same-domain judgment, and *every single one* still needed a real, bounded schema extension: the EU tracks forbearance as a dimension orthogonal to NPE status with no equivalent in `PRAMAN.CORE` today; Australia's EFS collection requires counterparty business-size tiering finer than `COUNTERPARTIES.SECTOR`; Hong Kong requires multi-entity (branch/subsidiary/combined) consolidation reporting with no `REPORTING_ENTITY_SCOPE`-equivalent concept in the schema at all; Singapore and Hong Kong both use instrument-type categories finer than the current `ADVANCES_FUND`/`ADVANCES_NONFUND` split. The accurate claim is "same domain bounds the *size* of the change to a new dimension or column, not a new domain" — not "same domain means no change."

**2. A new required design element: citation provenance/authority — found via Japan, not anticipated in the original four boundaries.** Japan's actual capital-adequacy notices are headed "(Provisional Translation)," with the Japanese original as the sole legally authoritative text (verified directly, not inferred). This is a genuine threat to Praman's core premise, not a translation nicety: every finding is supposed to be citation-backed and defensible to an examiner, and "sourced from a non-authoritative provisional translation" fails that bar. §4's circular-parser adaptor needs a companion requirement: `RULE_CORPUS` gains a provenance field (e.g. `SOURCE_AUTHORITY` + `ORIGINAL_LANGUAGE`) recording whether the ingested text is the authoritative original or a translation, and any citation the agent surfaces from a non-authoritative source must carry that caveat in its actual output, not just in internal documentation. RBI's circulars are English-original with no such layer, which is exactly why this project never needed to think about it before — a jurisdiction where it applies (Japan verified; South Korea pattern-matched; China and EU member-state transpositions flagged as unverified leads) is a qualitatively different ingestion requirement, not a config value.

Also from that research: the competitive-differentiation claim holds up under scrutiny (no vendor found does Praman's specific NL-circular → cited-mapping → governance-gate → pre-filing-validation loop), and the AI-in-RegTech market is growing roughly twice as fast as RegTech overall (~37% CAGR) — real support for the "real world relevance" judging criterion, not just an assertion.

## Actors, content acquisition, and the literal build order

`plug_and_play_build_plan.md` goes one level deeper than this doc: who actually does each step (mostly existing roles — `GOVERNANCE_WRITE` already has `INSERT` on `RULE_CORPUS`, so content curation was already scoped into the RBAC design, never exercised), the concrete design for how new circulars actually get in (a governed discovery queue, not open scraping — official-source allow-list + a scheduled watcher + mandatory human review, with a manual-upload escalation path for exactly the CAPTCHA/login-gated cases `data-sources.md` already hit once for real), the translation/provenance gate §4/finding #2 above requires in practice, and a phase-by-phase build sequence from an empty Snowflake account, with flow diagrams.
