# Is Praman actually jurisdiction-agnostic?

A component-by-component audit, prompted by the plan to eventually add a second jurisdiction and see whether the architecture genuinely generalizes or only looks like it does. Every claim below traces to a real file, not a guess — this is deliberately written the way this project's other docs are (`ingest/README.md`, `eval/results.md`): evidence first, verdict second.

The real question isn't "can we source another country's rules" — it's whether adding jurisdiction #2 requires touching *content* (new rule corpus, new `LINE_ITEM_MAP` rows, new synthetic-data anchors) or *architecture* (schema, detector logic, agent tool shapes, the ingestion pipeline itself). Content-only would be a strong validation of the design; anywhere it forces an architecture change is a real, useful finding about where India/RBI assumptions leaked in.

## ✅ Architecture-level, already jurisdiction-agnostic

- **The shared data model shape** — `GL_ENTRIES`/`POSITIONS`/`COUNTERPARTIES`/`TRANSACTIONS`/`AUDIT_LOG` (`sql/ddl/`). A general ledger, a position book, a counterparty master, a transaction feed, an audit trail — none of this is India-specific in shape. Any bank in any jurisdiction has some version of these four tables.
- **`RULE_CORPUS.JURISDICTION`** (`sql/ddl/01_rule_corpus.sql`) — already a real column (`VARCHAR(16)`, comment: `-- e.g. 'IN'`), not something that would need adding. The rule corpus was designed multi-jurisdiction from day one; it's just never held a second value yet.
- **`COUNTERPARTIES.JURISDICTION`** — same story: already generic, already populated with more than one value in practice (`'IN'` / `'Overseas'`, per `generator/generate_synthetic_data.py`'s `OVERSEAS_SHARE` sampling).
- **The RBAC model** — `ANALYST_READ` / `GOVERNANCE_WRITE` / `AUDIT_INSERT` / `OFFICER_SIGNOFF`, maker-checker, insert-only-by-grant audit logging (`sql/rbac/`). Maker-checker and append-only audit trails are universal regulatory-governance concepts, not an RBI invention — nothing here references India at all.
- **The `ZSCORE` UDF and its two consuming views** (`sql/detectors/`) — pure statistics (mean, stddev, trailing windows). Zero regulatory content, zero jurisdiction coupling.
- **`LINE_ITEM_MAP`'s governance *mechanism*** (`sql/ddl/02_line_item_map.sql`) — the proposed→approved gate, the `SOURCE_TABLE`/`SOURCE_COLUMN`/`TRANSFORM_LOGIC`/`RULE_CHUNK_ID` shape, is generic. Only the *rows currently in it* are India-specific (see below).
- **`SIGNAL_ASSURE_AGENT`'s Stage 2a/2b split** (line-item value validation vs. basic ledger-integrity checks) — this distinction is about *what kind of question is being asked*, not about which regulator's rules apply. Portable as-is.

## 🟡 Content-only change needed — schema and logic stay, the data changes

- **`LINE_ITEM_MAP` rows, `RULE_CORPUS` content, `generator/anchors.py`'s anchor figures.** A new jurisdiction needs its own real disclosure to bottom-up-reconcile a synthetic book against, and its own rule citations — but nothing about *how* `LINE_ITEM_MAP` or `RULE_CORPUS` work needs to change. The fragment-based exact-partition reconciliation algorithm in `generate_synthetic_data.py` is anchor-agnostic; only the anchor numbers are India/HDFC-specific.
- **`DIVERGENCE_DISCLOSURES`** (`sql/ddl/08_divergence_disclosures.sql`). The table *shape* (a reported value, a regulator-assessed value, the gap between them) is generic enough to represent any jurisdiction's version of "here's what we said, here's what the regulator found." But the table's own header comment calls it "**India-specific** ground truth #1... an India substitute for literal amended-vs-original filing pairs" — RBI's specific divergence-disclosure rule (public disclosure required when a bank's reported NPA diverges from RBI's inspection finding by more than a threshold) is not a mechanism every regulator has. A second jurisdiction might have literal amended-vs-original filing pairs instead (the originally-assumed, more common case) — meaning this table might not even be the right ground-truth source for jurisdiction #2, even though its columns would still work if it were.

## 🔴 Real hardcoding — this is where it would actually break

These aren't hypothetical; each is a specific file and line found by grepping for it, not assumed from the architecture description.

**Currency.** `CURRENCY VARCHAR(8) NOT NULL DEFAULT 'INR'` appears in three DDL files:
- `sql/ddl/04_positions.sql:11`
- `sql/ddl/06_gl_entries.sql:13`
- `sql/ddl/07_transactions.sql:11`

And `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml`'s `instructions.response` hardcodes: `"Format currency as INR (e.g. ₹1,234.56)."` A second currency's data would load fine (the column isn't constrained to `'INR'`, just defaulted), but the agent would keep formatting every answer in ₹ regardless of what currency the underlying rows actually use — a real, visible bug, not just an aesthetic gap. Cheap to fix (parameterize the default and make the response instruction currency-aware), but it's a genuine hardcoding, not a design that already handles it.

**`ingest/chunk_circular.py` is shaped around RBI's specific document structure, not a generic circular parser.** This is the single biggest real coupling point in the system. Concretely:
- `PREAMBLE_END_MARKERS` (line 34) is a hardcoded list of exact RBI preamble closing phrases ("hereby, issues Directions hereinafter specified.", "hereby, issue the Directions hereinafter specified.") — the function raises an error if a document's preamble doesn't end in one of these exact strings, by design (`ingest/README.md`: "raises rather than silently mis-chunking").
- `CHAPTER_RE` and `SUBSECTION_RE` (lines 39–40) are regexes built specifically around RBI Master Directions' "Chapter `<roman numeral>` - `<title>`" / "`<letter>`. `<title>`" nesting convention.

A different regulator's document format — the US Federal Register, UK PRA rulebooks, MAS notices — almost certainly doesn't share this exact structure. Ingesting a second jurisdiction's circulars would need a **new parser module**, not new configuration values in the existing one. This is the one place where "add a jurisdiction" is realistically a multi-day engineering task, not a data-loading task.

**`ACCOUNT_CODE` conventions** (`ADVANCES_FUND`, `ADVANCES_NONFUND`, `NPA_SUBSTANDARD`, `NPA_DOUBTFUL_1`, etc.) are `generator/generate_synthetic_data.py`'s own invented convention — nothing in the `GL_ENTRIES` schema enforces these specific strings (`ACCOUNT_CODE` is a plain `VARCHAR`). But the convention is *hardcoded downstream* in multiple places that would all need updating together if a new jurisdiction's generator used different codes:
- `sql/semantic_views/03_credit_exposure_sv.sql`'s `exposure_type`/`npa_classification` `CASE` expressions match these exact strings.
- `sql/detectors/03_gl_outlier_signals.sql` groups by `ACCOUNT_CODE` directly.
- `cortex_project/SIGNAL_ASSURE_AGENT.agent.yaml`'s orchestration instructions (both the Stage 2a citation logic and the new Stage 2b integrity checks) reference `ADVANCES_FUND`/`ADVANCES_NONFUND`/`NPA_*` by name.

Note that the *labels themselves* (Substandard/Doubtful/Loss) are actually reasonably portable — these come from Basel-derived asset-classification conventions used well beyond India, not an RBI-only vocabulary. The coupling isn't "these words are India-specific," it's "these exact strings are hardcoded in five places that would drift out of sync if changed in only one."

## The honest verdict

**Data model, RBAC, detector math, and the governance mechanism are genuinely jurisdiction-agnostic today** — that's a real, verifiable result, not aspirational. **Currency formatting and the `ACCOUNT_CODE` convention are minor, mechanical fixes.** **The circular-ingestion parser is the one piece that would need real new engineering**, because it was built to solve "parse this exact regulator's document structure," not "parse any regulator's document structure" — which was the right scope call for a hackathon single-jurisdiction build, but is the actual answer to "would this need architecture changes, not just content."
