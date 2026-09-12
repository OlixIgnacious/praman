# Problem Statement — Snowflake CoCo CLI Hackathon 2026 (GCC Edition)

**Organizer:** Hack2skill
**Track:** Risk, Fraud and Regulatory Intelligence Copilot (Banking / NBFC)
**Working title:** Regulatory Reporting Lifecycle Agent *(naming still open)*
**Prototype submission window:** 13–30 Sept 2026 · **Final Demo Days:** 27–30 Oct 2026
**Mandatory stack:** Snowflake CoCo CLI

---

## The track, verbatim

> Banking and NBFC teams manage real-time fraud, liquidity and credit risk, and regulatory reporting (AML, Basel, and local regulations) — largely manual today. Build a copilot that surfaces risk and fraud signals and produces audit-ready regulatory outputs from natural-language questions.

Two asks live inside that one sentence: **surface signals** (fraud, liquidity, credit risk — often real-time, often AML-adjacent) and **produce audit-ready regulatory outputs** (reporting — Basel, local regs). Most teams will pick one. We're building the spine that lets both sit on the same data model, because in practice they're the same problem asked from two directions: a signal is a candidate explanation for why a number moved, and a regulatory output is a claim about what the numbers mean.

## The problem

Regulatory reporting is the highest-volume, highest-liability language problem in banking, and it is still done largely by hand. A circular arrives as a PDF; analysts read it, argue about what it means, hunt through a mapping spreadsheet to work out which report fields move, and write a change spec. A quarter later, someone eyeballs a draft return against that same rule text before an officer signs it. When something is wrong — or a fraud/AML signal was missed — the bank takes a penalty and an analyst spends days tracing the number back through source systems to explain it.

Deterministic rule engines and statistical detectors already handle the arithmetic and the pattern-matching — cross-footing, validity edits, schema checks, outlier scoring. What nothing handles well is the part that is genuinely reading and reasoning: interpreting a circular, explaining *why* a flagged transaction or liquidity ratio looks the way it does, deciding what a rule change touches, and writing the explanation a regulator will accept. That's the gap this copilot fills — and it's squarely a natural-language reasoning problem, not a detection-engine problem.

## Who it is for

**Primary users:** regulatory reporting analysts, risk/fraud analysts, and their managers.
**Secondary:** data governance, internal audit, compliance officers reviewing AML/STR-adjacent output.
**Accountability is unchanged.** The signing officer (regulatory filings) or the compliance officer (AML/STR-adjacent disposition) remains responsible. The system is decision support and is never an autonomous filer or an autonomous investigator.

**Buyer:** mid-size banks, foreign bank branches, small/challenger banks, NBFCs and non-bank lenders, insurers — in any jurisdiction. Same obligations as a top-five bank, a fraction of the headcount. That asymmetry is the wedge, and it holds regardless of which regulator is on the other side.

## What it does — four stages of one lifecycle

**Stage 0 — Signal.** Surfaces risk and fraud signals from transaction, position, and exposure data in natural language: "why did our liquidity coverage ratio move 3pp this week," "which counterparties look like structuring," "flag credit exposures approaching concentration limits." Built on **Cortex Analyst** — Snowflake's semantic layer for NL-question-to-structured-insight over our transaction/position tables — so this stage is largely configuration (define the semantic model) rather than custom NL-to-SQL code. It flags candidates; it does not adjudicate. AML-adjacent flags route to a compliance queue with full reasoning attached, never to auto-filing — tipping-off risk and STR liability stay entirely with the human reviewer.

**Stage 1 — Interpret.** A new circular or taxonomy version arrives. Ingested via **Cortex Search** (Snowflake's managed RAG service for unstructured documents — PDFs, reports) so the raw circular text is queryable and citable directly, rather than us building our own document store. The agent parses it, maps changed requirements onto report line items and the firm's data fields, and produces a gap analysis, a change spec, and test cases. Genuine ambiguity is flagged for escalation rather than resolved confidently.

**Stage 2 — Assure.** Before filing, the agent validates a draft return against rule text (via Cortex Search over the rule store), the firm's own filing history, and peer benchmarks (via Cortex Analyst over historical filings). Output is a ranked list of findings, each carrying the rule paragraph it rests on. Statistical outlier scoring (deterministic) feeds this stage the same way it feeds Stage 0 — one detector, two consumers.

**Stage 3 — Explain.** A confirmed break or a confirmed signal is traced across lineage to ranked root causes, with a proposed remediation and a draft regulator-facing (or compliance-facing) narrative. Coco has demonstrated native, on-request lineage tracing (e.g. mapping every PII-tagged table back to a source table and forward to downstream dashboards, from a single prompt) — this is close to off-the-shelf for tracing a report line item back to its source GL/position rows, which is most of what Stage 3 needs.

The four share one spine: a **versioned rule store**, a **line-item-to-data-field map**, and the same underlying transaction/position data in Snowflake. Stage 0 queries it live, Stage 1 walks it forward, Stage 2 walks it backward, Stage 3 walks it down. Building that spine once — on one governed data model — is what makes this one product rather than four demos, and it's the direct answer to "produces audit-ready regulatory outputs from natural-language questions."

## Where the model is, and is not

| Deterministic | LLM (via Coco, model-garden: Claude Opus / GPT / Snowflake-native) |
|---|---|
| Cross-footing, arithmetic, unit checks | Circular interpretation (Cortex Search over rule corpus) |
| Published validation rule sets (DPM, MDRM edits) | Impact reasoning over schema |
| Schema and taxonomy conformance | Ambiguity detection |
| Peer/statistical outlier & anomaly scoring | Natural-language query → structured insight (Cortex Analyst) |
| Structuring/velocity pattern detection (rules-based) | Break/signal narrative and remediation drafting |
| | Multilingual rule ingestion |
| | Lineage trace narration (Coco's native lineage tracing) |

Every generated claim carries a rule citation and the rule version it was read from, or the query/data lineage it was computed from. No citation, no output.

## Scope

**Realistic prototype, by 30 Sept:** the submission window is roughly two and a half weeks from today (11 Sept). That's not enough time to deliver everything the original 18-Oct-scoped version of this idea called for. We're cutting scope hard rather than shipping four shallow demos:

- **One synthetic institution, one jurisdiction** — picked for the prototype purely on availability of real, machine-readable rule data to build and eval against, not as a market commitment. Not two of each.
- **Stage 0 (Signal) and Stage 2 (Assure) end-to-end and demoable** — these two are what the track literally asks for and what judges will see live: ask a natural-language question, get an audit-ready, citation-backed answer.
- **Stage 1 (Interpret) as a working slice**, not full breadth — one real circular fed through the pipeline, gap analysis produced, rather than a library of them.
- **Stage 3 (Explain)** as a scripted-but-real walkthrough on one injected break, showing the lineage trace — depth over polish.
- **Append-only audit log** for every question asked and every output produced — this is cheap to build and directly supports "audit-ready," so it stays in scope regardless of time pressure.
- A small, real eval slice (see below) with numbers we can defend live, even if it's not the full harness.

**Explicitly roadmap, stated as such in the demo:** second jurisdiction, second institution, full eval harness with published precision/recall per error type, maker-checker workflow integration, production connectors.

## Data

**Real:** circulars and equivalent regulatory notices/directions; report instructions; published validation rule sets (e.g. EBA DPM, FFIEC MDRM, or the equivalent for whichever jurisdiction is chosen); taxonomy versions; filed returns; amended-versus-original filing pairs; regulator penalty disclosures.

**Synthetic:** the institution's internal transaction/position data, schema mapping, lineage, and injected errors/signals — loaded into Snowflake as the system of record all four stages query against.

The synthetic firm is generated **bottom-up from real filings**: take a real published return and synthesize a GL, position set, and counterparty book that aggregates to those exact line items. Real numbers at the top, invented plumbing underneath. This inherits real-world shape (concentration, long tails, inter-line ratios) that hand-invented data never has, and it yields known-true lineage for Stage 3 and known-true signals for Stage 0 without needing anyone's production environment.

For the prototype: **one** deliberately realistic institution — a mid-size bank with enough derivatives/off-balance-sheet exposure to make both the reporting and the fraud/liquidity signal stories credible in one dataset. (Two-or-three-institution breadth moves to roadmap, per the scope cut above.)

## Evaluation

Three sources of ground truth, two of them real — kept as the target methodology even though the prototype will only exercise a slice of it live:

1. **Amended vs. original filings** — a published, real-world labelled set of "what was wrong and got corrected." Evaluates Stage 2 against actual errors real banks made.
2. **Taxonomy version diffs** — feed the agent circular *N*, compare predicted impacted fields against the real taxonomy delta. Precision and recall for Stage 1.
3. **Injected error/signal catalogue** — named types generated into the synthetic firm: classification, timing/cut-off, sign, unit/scale, double counting, stale reference data, defensible-interpretation differences, correct-but-anomalous cases that *should* survive scrutiny, and a handful of fraud/AML-adjacent structuring patterns for Stage 0.

Report **precision and recall per error type**, not one aggregate, on whatever slice we get running by demo day. Add an abstention/coverage note even if only qualitative: in this domain, an agent that escalates 20% and is right on the rest is deployable; one that is 92% accurate and silent about which 8% is not.

Tune for recall. A missed error or signal costs a penalty or a missed fraud loss; a false positive costs an analyst ten minutes.

## Guardrails and deliberate exclusions

- **Never auto-files or auto-actions.** No autonomous submission to a regulator, no autonomous SAR/STR filing, no autonomous account action. Human sign-off, always, on every stage.
- **AML is in scope as signal-surfacing and reporting-support only** — not as an autonomous transaction-monitoring or disposition system. The copilot explains and ranks; it never decides an STR gets filed, and it never contacts a customer or counterparty (tipping-off risk stays fully owned by the human compliance officer).
- **No customer-outcome decisions** (credit, pricing) — separate regulatory surface entirely, stays out of scope.
- **PII-minimal by design.** Returns are largely aggregates; Stage 0 and Stage 3 work on schema, transaction metadata, and aggregates wherever possible rather than raw customer PII.
- **Deploys into the customer's own Snowflake account**, respecting whatever region/data-residency the account is provisioned in. No bank sends draft filings or transaction data to an unrelated third-party SaaS.

## Audit and reproducibility

Append-only run log: prompt, model version, retrieved rule text with version (or query + data snapshot for Stage 0), output, human decision. Model and rule versions pinned so a 2026 assessment re-runs identically later. Maker-checker sign-off recorded. Exportable evidence pack for inspection.

**Framed against BCBS 239 with a real column-to-principle mapping, not just a citation.** BCBS 239 (Principles for effective risk data aggregation and risk reporting) names four risk-data-aggregation principles the audit log directly satisfies:

| BCBS 239 principle | `AUDIT_LOG` column(s) |
|---|---|
| Accuracy and integrity — data can be validated and traced to source | `RUN_ID` (unique per run), `MODEL_VERSION` and `QUERY_SNAPSHOT_ID`/`RETRIEVED_RULE_CHUNK_IDS` (pin the exact model and data/rule version an output came from, so it can be independently re-verified) |
| Completeness — capture substantially all material risk data | Every Skill invocation writes a row (enforced by `AUDIT_INSERT`'s grant, not a logging convention an engineer could forget) — `PROMPT_OR_QUESTION`, `OUTPUT`, and the retrieved evidence are captured for every run, not a sample |
| Timeliness — data can be generated and reported promptly | `RUN_TIMESTAMP`, defaulted at write time — every run is timestamped at the moment it happened, supporting on-demand reporting without a separate reconciliation step |
| Adaptability — flexible, ad hoc risk data aggregation for a range of reporting needs | `STAGE` separates Signal/Interpret/Assure/Explain, so a reviewer can query by stage, date range, or user directly against `AUDIT_LOG`/`AUDIT_EVIDENCE_PACK` rather than needing a bespoke report for each request |

`HUMAN_DECISION`/`SIGNOFF_BY`/`SIGNOFF_AT` additionally support BCBS 239's governance principles (senior management/board oversight of risk reporting) by recording who signed off and when, as a new row rather than an edit — which is also what makes the log itself tamper-evident, the accuracy/integrity property applied to the log's own construction.

## Markets

The product is jurisdiction-agnostic by design: the versioned rule store and the line-item-to-data-field map are the reusable parts, and a new regulator is a new rule corpus and a new mapping, not a new architecture. RBI, MAS, APRA, HKMA, EU (COREP/FINREP), and UK regimes are all viable targets, and regulators converging on XBRL and shared data-point models means adding one is content work, not a rewrite. Which single jurisdiction backs the prototype is a data-availability decision (see Scope/Data), not a market bet — it doesn't imply that jurisdiction is a priority go-to-market target.

**A US expansion specifically is now a de-risked path, not just an assertion.** Snowflake's own Marketplace hosts "Snowflake Public Data (Free)" (SEC, Federal Reserve, FDIC, BLS, BEA data via Secure Data Sharing, zero ETL) — and its SEC XBRL data, tagged with the `us-gaap` taxonomy, is functionally the same kind of structured, field-level validation/taxonomy layer we spent significant effort trying to get from RBI's Sankalan portal (and only partly got). FDIC's banking-sector metrics could anchor a second synthetic firm the same way HDFC's Pillar 3 disclosure anchors India, without repeating the scraping/CAPTCHA/dead-end-circular work this jurisdiction cost. This doesn't change the current build (still India, still in scope), but it means "second jurisdiction" on the roadmap has one concrete, low-effort candidate already sitting in Snowflake rather than requiring the same ground-up sourcing effort for every future jurisdiction.

## Impact

Rather than inventing hour-savings, aggregate the chosen jurisdiction's regulator's published monetary penalty disclosures by year and by cause. This reframes the pitch from "saves analyst time" to "avoids penalties and regulator censure," which is what actually moves budget and maps directly onto the judging criterion of real-world relevance — and the same argument holds no matter which regulator's numbers we pull.

**Done, not just proposed — real RBI enforcement data, sourced and aggregated (`data-sources.md` item 6):**

RBI took **79 enforcement actions** against banks/NBFCs in FY24-25, totaling **₹32.9 crore** (₹3,291.5 lakhs) in monetary penalties (source: FACE's compilation of RBI's own published press releases, `data/raw/penalties/RBI_enforcement_penalty_compilation_FY24-25.pdf`). Banks account for 38% of actions but **82% of the penalty amount** (30 actions, ₹26.8 Cr) — concentration matters more than count for the pitch. NBFCs are 60% of actions but only 18% of the amount (48 actions, ₹5.7 Cr).

**By cause** (classified against all 79 detailed action descriptions in the source annex; primary cause per action, judgment call for the small number of multi-issue entries):

| Cause | Actions | Share |
|---|---|---|
| Corporate governance / shareholding / management-change violations | 20 | 25.3% |
| KYC / customer identification failures (risk categorization, UCIC, ineligible accounts) | 18 | 22.8% |
| Fair Practices Code / interest-rate & loan-term disclosure | 18 | 22.8% |
| Outsourcing / vendor oversight (LSP/DLA due diligence) | 6 | 7.6% |
| Regulatory reporting (CRILC/CIC/LRS/large-exposure breach reporting) | 6 | 7.6% |
| Digital lending / P2P platform structural violations | 6 | 7.6% |
| Prudential / deposit-education-fund / other | 3 | 3.8% |
| AML / fraud-adjacent | 2 | 2.5% |

**This corrects an assumption in an earlier draft of this pitch, not confirms it.** The claim that "a meaningful share [is] fraud/AML-adjacent" doesn't hold against the real FY24-25 data — AML/fraud-adjacent causes are the *smallest* category at 2.5%, not a meaningful share. What the real data actually supports: governance, KYC, and Fair Practices Code failures together account for **71% of all actions** — exactly the category of error Praman's Stage 0 (Signal) and Stage 2 (Assure) are built to catch before a draft return or a compliance gap becomes a public enforcement action, while the AML/fraud-adjacent share, though small by count, is precisely the guardrailed signal-surfacing-only slice `signal-query.SKILL.md` already handles (flag for compliance review, never auto-resolved). State the pitch's impact claim this way — "governance/KYC/disclosure failures are ~71% of real enforcement actions, exactly what Stage 0/2 targets" — rather than the original, uncorroborated "large share reporting, meaningful share fraud" framing.

Adoption path: **shadow mode** for two quarters alongside the existing team, accumulating an accuracy record before anyone relies on it.

## Scalability and moat

Per-jurisdiction rule ingestion is one-time plus circular deltas. The per-customer unit of work is the schema mapping — and that mapping compounds across customers and jurisdictions once it lives as governed data in Snowflake. The accumulated regulation-to-data-field map is the asset, not the prompts.

## Stack

Resolved against the hackathon's own Coco Starter workshops (Sept 2026) — Coco (formerly "Cortex Code") is not just dev-workflow tooling wrapped around a bring-your-own LLM. It's a data-native agent with its own reasoning layer, and most of our architecture maps onto existing Snowflake primitives rather than custom build:

- **Reasoning layer:** Coco's built-in model garden (Claude Opus, GPT, Snowflake-native models), hosted inside Snowflake — data and context never leave the account, which is a clean answer to the "customer's own environment" guardrail below.
- **Stage 0 (Signal):** Cortex Analyst — semantic layer over structured data, NL question in, structured insight out.
- **Stage 1 & Stage 2 rule/document retrieval:** Cortex Search — managed RAG over unstructured PDFs (circulars, rule text), with native citation back to source.
- **Stage 3 (Explain):** Coco's native lineage tracing, prompted directly ("show lineage from source table to downstream report") rather than a lineage engine we build.
- **Reusable logic:** package each stage's domain logic as a Snowflake **skill** (Coco's unit of reusable, governed capability — 100+ exist natively for governance/ML/cost; we add regulatory-specific ones). Skills are shareable and RBAC-governed within an org, which is useful once this moves beyond one team.
- **Productization:** the **Coco Agent SDK** to embed the four-stage copilot into our own review UI, rather than exposing the raw CLI to analysts — this is how the hackathon demo becomes a product rather than a terminal session.
- **Governance/audit:** native Snowflake RBAC and session/run history cover a meaningful share of the audit-log requirement below for free — worth building on top of rather than duplicating.
- **Deployment:** Snowflake is cloud-agnostic (AWS/Azure/GCP, chosen at account creation) — "deploy in the customer's own environment" becomes "the customer's own Snowflake account/region," not a GCP-specific claim.

Deterministic validation and outlier scoring in Python/SQL against Snowflake, invoked as skills; review UI as a lightweight web front end built on the Coco Agent SDK.

## Open items

- Which jurisdiction backs the prototype, based on real, machine-readable rule/eval data availability — decides the answer to several open questions below.
- Confirm Snowflake's regional availability against whatever data-residency requirement that jurisdiction imposes — not covered in the workshops; check current region list once the jurisdiction is picked.
- Team size and role split — decides how parallel Stages 0–3 can be built in a ~2.5-week window.
- Which single circular / taxonomy delta to use for the live Stage 1 demo.
- Whether to build regulatory logic as formal Snowflake skills (more setup, reusable/shareable, cleaner demo of the platform's own skill-sharing story) or as direct prompts/scripts (faster to get running) — worth a quick spike given the short timeline.
- Product name.
