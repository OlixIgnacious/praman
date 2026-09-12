# Regulatory landscape research — cross-market findings

Four parallel research passes, prompted by `plug_and_play_architecture.md`'s §0 domain-coverage question and the concrete JPX/securities-trading example that exposed it. Covers: US/UK/EU, Singapore/Hong Kong/Australia, Japan (banking + securities-market-conduct + cross-market translation risk), and the current practitioner/vendor landscape. Every finding below traces to a real source (listed at the end) or is explicitly flagged as unverified/inferred — following this project's established evidence-first discipline.

## Executive summary

1. **Every banking-prudential market researched (US, UK, EU, Singapore, Hong Kong, Australia) falls inside Praman's existing credit-risk/exposure domain** — none needs a new domain schema. But **none is a pure "reseed `LINE_ITEM_MAP` and go" case either.** Every single one needs a real, bounded schema extension: the EU's forbearance dimension, Australia's counterparty business-size tiering, Hong Kong's multi-entity (branch/subsidiary/combined) consolidation, Singapore/Hong Kong's finer instrument-type categories. `plug_and_play_architecture.md`'s §§1-4 framing needs softening: "same domain" does not mean "zero schema change."
2. **Japan's securities-market-conduct domain (JPX) confirms the different-domain case, with zero schema overlap** — a `TRADES` table (stock code, execution timestamp, price, quantity, counterparty/member IDs) would be needed from scratch, plus sequence/relationship-based detectors structurally different from Praman's per-entity z-score baselines (wash-trading/spoofing need order-book and cross-account graph analysis, not a single counterparty's own history).
3. **New finding, not anticipated when this research was scoped: language/translation is a citation-accuracy risk, not an ingestion inconvenience.** Verified directly for Japan — capital-adequacy notices are headed "(Provisional Translation)," with the Japanese original as the sole legally authoritative text. This is a direct threat to Praman's core "citation-backed" premise: a citation sourced from a non-authoritative translation could misstate what the actual rule requires, and would not hold up to an examiner asking "show me the rule this is based on." See the Architecture Implications section — this needs an actual design response, not just a caveat.
4. **Competitive positioning holds up under real scrutiny.** No vendor found (AxiomSL, OneSumX Reg Manager, Regnology, Vermeg, Squirro) does Praman's specific loop: NL circular → cited line-item mapping proposal → governance approval gate → pre-filing validation against that same governed mapping. The closest shipped capability is regulatory-change *monitoring* (flagging that a new rule might be relevant), not this. Caveat: based on public marketing/search content, not hands-on product testing — state as "no public evidence of this capability existing," not "definitively absent."
5. **RegTech market context supports the "real world relevance" judging criterion.** RegTech overall ~$21.8B (2026, ~15.7% CAGR); the AI-in-RegTech subsegment specifically ~$3.51B (2026) growing to a projected $12.33B by 2030 (~36.9% CAGR) — the AI-specific slice is growing roughly twice as fast as the category overall.
6. **The RBI-derived "71% governance/KYC/FPC, 2.5% AML-adjacent" enforcement-cause split is directionally consistent elsewhere, but thinly evidenced.** Two named UK PRA penalties (UK Insurance Limited, £10.6m, a Solvency II calculation error; Barents Reinsurance, £1.785m, governance/reporting-controls failures) are both control/calculation failures, not fraud/AML — consistent with, but nowhere near proof of, a generalized cross-market pattern. N=2.

## Per-market findings

### United States

- **Reports:** FFIEC Call Report (031/041/051), FR Y-9C (holding companies), CCAR/DFAST stress testing.
- **Field spec:** The Fed's MDRM (Micro Data Reference Manual) — real, public, actively maintained, but PDF/web-based rather than natively machine-readable. A third-party project (`andenick/bank-data-dictionary` on GitHub) reconciles MDRM + Call Report schedules into JSON/validation rules — real and current, but unofficial.
- **Language:** English only.
- **Format:** Quarterly, XBRL via FFIEC's Central Data Repository.
- **Taxonomy fit:** Schedule RC-N's past-due/nonaccrual-by-loan-category ladder is conceptually the same domain as `NPA_<classification>` — category labels and day-count thresholds differ and need real mapping, not a rename.

### United Kingdom

- **Reports:** PRA/FCA — the UK incorporated the *full EBA COREP/FINREP framework* directly into UK rules (aligned to EBA Taxonomy 3.0) post-Brexit, rather than designing its own.
- **Field spec:** Inherits the EU's DPM-based definitions (below) with UK-specific deltas. Submitted via BEEDS (Bank of England's XBRL portal).
- **Language:** English only.
- **Taxonomy fit:** Same conclusion as the EU, since it's the same underlying framework.

### European Union

- **Reports:** COREP (capital adequacy) and FINREP (financial reporting) under EBA's harmonized ITS framework; national competent authorities are the actual first-level collection point.
- **Field spec:** The **DPM (Data Point Model)** — genuinely the best-published, most machine-readable field-level spec of any market researched (better than what `data-sources.md` found for RBI): official DPM table layouts, XBRL taxonomy archives, filing rules, all freely downloadable from eba.europa.eu.
- **Language — real, structural multi-language dimension.** EBA's ITS/templates are officially translated into all EU official languages; XBRL data-point *codes* are language-independent, but a bank's actual guidance and a national regulator's own supplementary rules can be local-language-only.
- **Taxonomy fit — a genuine, non-trivial extension, not just relabeling.** EBA's NPE definition is conceptually the same severity-ladder domain as RBI's, but **forbearance is tracked as a separate, orthogonal dimension** (an exposure can be performing-forborne or non-performing-forborne, independent of its NPE status) — Praman's current `ACCOUNT_CODE` taxonomy has no equivalent concept at all.

### Singapore (MAS)

- **Reports:** MAS Notice 610 ("Submission of Statistics and Returns") + Notice FHC-N610.
- **Fields:** Monthly/quarterly balance-sheet and exposure statements — same domain as Praman.
- **Language:** English only.
- **Format:** Unverified whether a public XBRL taxonomy exists (likely MAS's own portal/template system) — flagged, not assumed.
- **Taxonomy fit:** Instrument-type categories (Reverse Repo, NCDs, Debt Securities, Equity, Loans/Advances/Bills) more granular than the current `ADVANCES_FUND`/`ADVANCES_NONFUND` split — real extension needed.

### Hong Kong (HKMA)

- **Reports:** The MA(BS) return series (MA(BS)1 = full balance sheet, plus numbered forms for specific slices), legal basis Banking Ordinance s.63.
- **Language:** All documents found are served under an English (`/eng/`) path; Hong Kong law is officially bilingual, but whether a Chinese-language version of the completion instructions is independently authoritative (vs. an administrative translation) was **not confirmed** — flagged, not assumed either way.
- **Format:** Unverified public XBRL taxonomy; likely a dedicated online returns system.
- **Taxonomy fit — a real structural gap, not just categories.** Institutions with overseas branches file a combined HK+overseas return alongside the HK-only one — **multi-entity consolidation logic Praman's schema has no dimension for at all** (no `REPORTING_ENTITY_SCOPE` concept exists today).

### Australia (APRA)

- **Reports:** The EFS (Economic and Financial Statistics) collection — ARS 112.2 (standardised credit risk), ARS 220.0/720.1 (credit quality/non-performing, explicitly aligned to APS 220), ARS 180.0 (counterparty credit risk).
- **Field spec & format — the strongest machine-readable confirmation of any market researched.** APRA publishes real XBRL Reporting Taxonomies per D2A (Direct to APRA) form; Reporting Standards and Practice Guides are freely published PDFs.
- **Language:** English only.
- **Taxonomy fit — confirmed finer-grained than Praman's model, as `jurisdiction_agnostic_analysis.md` suspected.** EFS counterparty classification includes an explicit **small/medium/large business-size breakdown** aligned to BCBS/APRA IRB standards — materially finer than `COUNTERPARTIES.SECTOR` (industry only, no size tier) — a real, bounded schema extension, not a content-only change.

### Japan — banking (JFSA)

- **Regime:** Basel III implemented via domestic notifications, not one consolidated circular series like RBI's Master Directions — reporting is notification/ordinance-driven.
- **Asset classification — a real, different taxonomy, not RBI's Substandard/Doubtful/Loss.** Japan's self-assessment framework uses five borrower categories (Normal, Needs Attention [+ Needs Special Attention sub-tier], In Danger of Bankruptcy, Effectively Bankrupt, Bankrupt); NPL disclosure under the Financial Reconstruction Act aggregates the bottom four. Confirms this is real content/mapping work, not a relabeling.
- **Language — verified directly, not inferred.** The actual capital-adequacy notice fetched is headed **"(Provisional Translation)"**; a separately-published Japanese version is the legally authoritative text. See the cross-cutting translation finding below.

### Japan — securities market conduct (JPX/FIEA)

- **Confirmed: zero overlap with Praman's canonical schema.** The closest verified named regime is the Large Shareholding Reporting System (ownership disclosure, not trade execution). The actual trade-surveillance function is JPX's self-regulatory market surveillance under FIEA Article 84, structurally similar to EU MiFID II/MiFIR Article 26 (RTS 22) transaction reporting and the US Consolidated Audit Trail — both require, per trade: instrument identifier, execution timestamp, price, quantity, counterparty identifiers. **The exact Japan-specific field schema was not independently verified in this pass** — the MiFID/CAT shape is the right reference approximation, not a confirmed JPX citation.
- **A concrete new-table sketch, not built:** `TRADES(TRADE_ID, STOCK_CODE, ISIN_OR_LOCAL_CODE, TRADE_DATE, EXECUTION_TIMESTAMP, SETTLEMENT_DATE, PRICE, QUANTITY, SIDE, EXECUTING_MEMBER_ID, COUNTERPARTY_MEMBER_ID, ACCOUNT_ID, ORDER_ID)`.
- **Detector pattern is different in kind, not just threshold.** Praman's `ZSCORE`-based approach baselines one counterparty against its own history. Market-conduct surveillance (wash-trading, spoofing, layering) needs sequence- and relationship-based detection instead: order-to-trade ratios, price impact around order placement/cancellation (needs order-book depth, not just executed trades), and cross-account/beneficial-ownership graph analysis. Insider-trading-adjacent detection needs trade-timing correlation against corporate-disclosure timestamps — a temporal-correlation problem, not a per-entity baseline. Presented as general market-surveillance practice, lower confidence than the verified findings above.

## Cross-cutting finding: language/translation as a citation-accuracy risk

This is the one finding that changes the architecture, not just the content plan.

- **Japan (verified):** English is explicitly non-authoritative ("Provisional Translation"); Japanese is the legal source.
- **South Korea (pattern-matched, not independently confirmed):** English translations published via a dedicated portal separate from the FSC's own regulations — structurally the same "courtesy translation, statute is authoritative" pattern, but not confirmed to carry the same explicit "provisional" disclaimer Japan's does.
- **Not verified this pass, listed as leads only:** China (CBIRC/NFRA text is Chinese-original; English versions where they exist are typically unofficial/law-firm-produced); EU member states can each transpose a directive into their own national language, with that transposition — not the EU's central text — being the legally operative version domestically, even though the EU directive itself has equal-authority versions in every official language.

**Why this matters specifically for Praman, not generically:** the whole product premise is citation-backed accuracy — every finding traces to a specific rule paragraph, defensible to an examiner. If the ingested source text is a non-authoritative translation, a citation could misstate what the authoritative original actually requires (translation drift, a translation that lags the original's amendments, or plain imprecision), and "sourced from a provisional English translation" is not a defensible answer to "show me the rule this is based on." RBI's circulars are English-original with no translation layer — this risk doesn't currently exist anywhere in Praman's build, but adding a jurisdiction where it does exist is a qualitatively different pipeline requirement, not a config change.

## Competitive landscape (practitioner research)

- **Named vendors and what they actually cover:** AxiomSL/SS&C (data aggregation + calculation + filing across 170+ regulators — not NL interpretation), Wolters Kluwer OneSumX Reg Manager (AI-powered regulatory-change categorization with lineage to "examiner-ready evidence" — the closest analogue found, but change-monitoring, not mapping-and-validation; primary product page returned HTTP 403, description sourced from secondary snippets), Regnology (Chartis 2025 Category Leader, calculation/submission focus), Vermeg (liquidity/regulatory reporting, Europe-strong), Squirro (retrieval-grounded compliance Q&A with audit trails — confirmed via direct fetch it does *not* do field-level mapping of a directive to report line items or citation-backed pre-filing validation).
- **Analyst pain points, matching Praman's own framing:** regulatory material fragmented across databases/drives/email (tens of thousands of pages across jurisdictions for a mid-sized institution); keyword search can't tell an analyst a circular *modifies* a base regulation (no relationship-awareness); manual approval cycles are slow (automated workflows cut approval-cycle time ~50% where adopted, per a Wolters Kluwer survey referenced in secondary sources).
- **Named-bank RegTech spend (unverified claim, flagged):** HSBC, Deutsche Bank, and JPMorgan each reportedly spend over $1B annually on RegTech — secondary-source claim, not confirmed against a primary bank disclosure.

## Architecture implications — what this changes in `plug_and_play_architecture.md`

1. **Soften §§1-4's "same domain = adaptor + reseed, no schema change" framing.** Every single banking-prudential market researched needed a real, bounded schema extension even though all fell inside the existing domain. The accurate framing is "same domain bounds the *size* of the change (a new dimension/column, not a new domain), it doesn't mean *zero* change."
2. **A concrete backlog of candidate schema extensions, now evidenced rather than hypothetical:** a forbearance dimension (EU), counterparty business-size tiering (Australia), a `REPORTING_ENTITY_SCOPE`-style multi-entity consolidation concept (Hong Kong), finer instrument-type `ACCOUNT_CODE` granularity (Singapore/Hong Kong).
3. **A new, required design element: citation provenance/authority.** Any ingested source document needs an explicit flag — authoritative-original-language vs. translation, and if a translation, which language it was translated from and whether the source itself claims provisional/non-authoritative status. This likely means a new `RULE_CORPUS` column (e.g. `SOURCE_AUTHORITY` or `IS_AUTHORITATIVE_TEXT` + `ORIGINAL_LANGUAGE`), and every citation the agent surfaces for a non-English-original jurisdiction should carry that caveat explicitly in its output, not just in internal documentation. This is new, real work `plug_and_play_architecture.md`'s original four boundaries didn't anticipate.
4. **§0's domain-coverage judgment holds up well overall** — Japan's securities-trading case is a confirmed, unambiguous different-domain example; every banking-prudential market researched confirmed the same-domain judgment. The framework itself doesn't need to change, just the "same domain → no schema change" corollary (point 1 above).

## Sources

**US:** [Fed MDRM](https://www.federalreserve.gov/apps/mdrm/data-dictionary) · [bank-data-dictionary (GitHub)](https://github.com/andenick/bank-data-dictionary) · [FFIEC Call Report downloads](https://cdr.ffiec.gov/public/HelpFiles/DownloadHelp.htm) · [FFIEC 031/041 RC-N instructions](https://www.fdic.gov/resources/bankers/call-reports/crinst-031-041/2019/2019-03-rc-n.pdf)

**UK/EU:** [EBA Reporting Framework v2.0](https://www.eba.europa.eu/risk-and-data-analysis/reporting-frameworks/reporting-framework-v20) · [EBA/EIOPA XBRL taxonomy architecture](https://www.eba.europa.eu/sites/default/files/document_library/Risk%20Analysis%20and%20Data/Reporting%20Frameworks/Reporting%20framework%203.4/1054952/EBA%20and%20EIOPA%20taxonomy%20architecture%20v2.0-20230424.pdf) · [Bank of England BEEDS](https://www.bankofengland.co.uk/statistics/data-collection/beeds) · [EBA supervisory reporting](https://www.eba.europa.eu/regulation-and-policy/supervisory-reporting) · [EBA/GL/2018/10 non-performing/forborne exposures](https://www.eba.europa.eu/sites/default/files/document_library/Publications/Guidelines/2022/1041279/Consolidated%20%20GL%20on%20disclosure%20of%20non-performing%20and%20forborne%20exposures.pdf)

**Singapore/Hong Kong/Australia:** [MAS Notice 610](https://www.mas.gov.sg/regulation/notices/notice-610) · [HKMA submission of returns](https://www.hkma.gov.hk/eng/key-functions/banking/banking-regulatory-and-supervisory-regime/regulatory-supervisory-framework/submission-of-returns/) · [HKMA Banking Regulatory Document Repository](https://brdr.hkma.gov.hk/) · [APRA ARS 112.2](https://www.apra.gov.au/system/files/Final-ARS-112.2.pdf) · [APRA RPG 701.0](https://www.apra.gov.au/sites/default/files/2024-04/RPG%20701.0%20ABS_RBA%20Reporting%20Concepts%20for%20the%20EFS%20Collection.pdf) · [APRA taxonomies/D2A/XBRL](https://www.apra.gov.au/information-about-taxonomies-d2a-and-xbrl)

**Japan:** [FSA capital adequacy implementation timeline (Provisional Translation)](https://www.fsa.go.jp/en/news/2020/20200414_capital.html) · [BOJ Quarterly Bulletin, asset self-assessment, Nov 2002](https://www.boj.or.jp/en/finsys/fs_policy/data/fss0210a.pdf) · [FSA FAQ on FIEA §5, large shareholding reporting](https://www.fsa.go.jp/en/laws_regulations/faq_on_fiea/section05.html) · [JPX outline of self-regulatory operations](https://www.jpx.co.jp/english/regulation/outline/about/index.html) · [Financial Instruments and Exchange Act, official translation](https://www.japaneselawtranslation.go.jp/en/laws/view/2355/en) · [JPX timely disclosure guidebook](https://www.jpx.co.jp/english/equities/listing/disclosure/guidebook/) · [MiFID II transaction reporting overview](https://www.kaizenreporting.com/regulations/mifid-ii-transaction-reporting/)

**Practitioner landscape:** [Nasdaq AxiomSL](https://www.nasdaq.com/solutions/fintech/nasdaq-axiomsl/regulatory-reporting) · [Wolters Kluwer OneSumX Reg Manager launch](https://www.wolterskluwer.com/en/news/wolters-kluwer-launches-ai-powered-onesumx-reg-manager) · [Chartis Regnology Vendor Spotlight 2025](https://www.regnology.net/ecomaXL/files/Chartis_Regnology_Vendor_Spotlight_2025.pdf) · [Squirro compliance workflow automation](https://squirro.com/squirro-blog/compliance-workflow-automation) · [PRA fines Barents Reinsurance](https://www.bankofengland.co.uk/news/2025/july/pra-fines-barents-reinsurance-sa-london-branch) · [OCC Fall 2024 Semiannual Risk Perspective](https://www.occ.gov/news-issuances/news-releases/2024/nr-occ-2024-135.html) · [RegTech Market Report 2026](https://www.researchandmarkets.com/reports/5939382/regtech-market-report) · [AI in RegTech Market](https://www.researchandmarkets.com/report/global-artificial-intelligence-in-regtech-market)
