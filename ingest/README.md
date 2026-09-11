# Citation chunking — how `chunk_circular.py` works

How a scraped RBI Master Direction becomes citable `RULE_CORPUS` rows. This exists because Stage 1/2/3 all need to point at a specific obligation ("para 21 of RBI/DoS/2026-27/415"), not just "the document" — the chunk grain and the metadata carried on each chunk are what make that citation possible.

## Why paragraph-level, not fixed-size

Cortex Search (see `sql/create_rule_corpus_search.sql`) will happily index chunks of any size — it doesn't dictate chunk boundaries. The boundary choice here is deliberate: **RBI's own numbered paragraph is the citable unit** — this is literally how these documents are referenced in practice ("para 21", "clause 4(2)"). Chunking any other way (fixed token windows, sentence splitting, one-chunk-per-document) would produce citations that don't map onto anything a regulator, auditor, or analyst would recognize as a reference.

The cost of this choice: chunks are uneven in size. Para 21 (the list of applicable returns) is a ~15,700-character table; para 1 is one sentence. That's fine — a citation should point at the paragraph that carries the obligation, however long that paragraph happens to be.

## Source format

Circulars are scraped as plain text (`notebooks/rbi_scraping.ipynb`), not parsed from a PDF — so there's no `PARSE_DOCUMENT` step for this source type, and no real page boundary to record (`PAGE_NO` is left `NULL`). Each file (`data/raw/circulars/*.txt`) looks like:

```
RBI/DoS/2026-27/415 | DoS.CO.DSG.9/33.01.001/2026-27
Reserve Bank of India (Commercial Banks - Supervisory Returns) Directions, 2026
Issued: July 31, 2026
Source: https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13638

---

Chapter I - Preliminary A. Short Title and Commencement B. Applicability C. Definitions ... [table of contents,
inline, no line breaks] ... In exercise of powers conferred under Section 27 ... hereby, issues Directions
hereinafter specified. Chapter I - Preliminary A. Short Title and Commencement 1. These Directions shall be
called the Reserve Bank of India (Commercial Banks - Supervisory Returns) Directions, 2026. 2. These
Directions shall come into effect immediately upon issuance. B. Applicability 3. These Directions shall be
applicable to Commercial Banks ... [body continues as one line] ...
```

Four things make this parseable without a full NLP pipeline:
1. A fixed preamble sentence ("...hereby, issues Directions hereinafter specified.") separates the table of contents (pure navigation, no obligation to cite) from the real body — everything before it is discarded.
2. Chapters ("Chapter I - Preliminary"), subsections ("A. Short Title and Commencement"), and numbered paragraphs ("1.", "2.", ...) repeat inline in the body, immediately before their actual content — so header text and paragraph text sit right next to each other with no visual separation.
3. Paragraph numbers are **strictly sequential starting at 1**, with no gaps.
4. Table rows inside a paragraph (e.g. para 21's list of returns) use bare numbers ("1 Return on Asset Liability...") with no trailing period — so they never collide with the "N. " pattern real paragraph markers use.

## The algorithm

1. **Strip the table of contents.** Find the preamble's closing phrase, keep only what comes after it as `body`.
2. **Find every numbered paragraph, in strict sequence.** Rather than one regex sweep over the whole body (which risks a stray `"N."` inside a table matching out of order), the search is sequential: find `"1. "` first, then search *only after that position* for `"2. "`, then `"3. "`, and so on. This is what makes the bare-number table rows harmless — even a rogue `"5 "` inside a table can't be mistaken for paragraph 5, because the search for `"5. "` only starts after paragraph 4 was already found, and a plain number with no trailing period never matches at all.
3. **Locate chapter and subsection headers** via two regexes anchored on what always follows them: a chapter header is text between `"Chapter <roman> -"` and the next subsection letter; a subsection header is a single capital letter + period followed by title-case words, immediately before the next numbered paragraph.
4. **Slice each paragraph's text**, from its own number to the start of the next paragraph — trimming off any chapter/subsection header that falls inside that span first (see below).
5. **Build `SECTION_REF`** by looking up the most recent chapter and subsection header whose offset precedes the paragraph, e.g. `"Chapter III - Filing of Supervisory Returns > B. List of Applicable Returns > para 21"`.

### The boundary bug this caught

First pass sliced each chunk from its own paragraph number straight to the *next* paragraph's number. That's wrong whenever a subsection header sits between them — e.g. between para 21's content and para 22's number, the source has `"...armed guards, alarm system, and other security measures provided. C. Timelines 22. The timelines..."`. Slicing straight to `"22."` pulled `"C. Timelines"` onto the *end* of chunk 21, even though that header belongs to chunk 22 (and is already captured there via `SECTION_REF`, not chunk text).

Fix: after computing the naive end-of-chunk offset, check whether any chapter/subsection header offset falls inside that span — if so, cut there instead. Verified against every chapter/subsection transition in the 415 circular; no bleed either direction.

## Example output

Three real rows from `data/processed/rule_corpus_chunks.csv` (chunking `RBI_DoS_2026-27_415_..._Supervisory_Returns_Directions_2026.txt`):

**A short, single-sentence paragraph:**
```
CHUNK_ID:     RBI/DoS/2026-27/415#1
SECTION_REF:  Chapter I - Preliminary > A. Short Title and Commencement > para 1
CHUNK_TEXT:   1. These Directions shall be called the Reserve Bank of India
              (Commercial Banks - Supervisory Returns) Directions, 2026.
```

**A paragraph with nested sub-items — the `(1)`, `(2)` markers stay inside the chunk, since they're part of paragraph 4's own content, not separate citable units:**
```
CHUNK_ID:     RBI/DoS/2026-27/415#4
SECTION_REF:  Chapter I - Preliminary > C. Definitions > para 4
CHUNK_TEXT:   4. In these Directions, unless the context states otherwise, the terms
              herein shall bear the meaning assigned to them below: (1) 'Centralised
              Information Management System (CIMS)' refers to an online...
```

**The boundary case — para 22 starts clean, with no trailing text from para 21 or the "C. Timelines" header that precedes it in the source:**
```
CHUNK_ID:     RBI/DoS/2026-27/415#22
SECTION_REF:  Chapter III - Filing of Supervisory Returns > C. Timelines > para 22
CHUNK_TEXT:   22. The timelines with respect to Reference Date for submission of
              returns will depend on the frequency at which the return is to be
              submitted, unless mentioned otherwise. The timelines are given below...
```

Full run against the 415 circular: **30 chunks, one per numbered paragraph (1 through 30), zero gaps, zero duplicates** — verified by inspecting every chapter/subsection transition, not just spot-checked.

## Known limits

- **Assumes every chapter has lettered subsections starting at A.** True for both circulars sourced so far (412, 415); a Master Direction with an un-lettered chapter would need the subsection regex loosened.
- **One preamble phrase per document family, hardcoded** in `PREAMBLE_END_MARKERS`. A newly-scraped circular with different boilerplate needs its exact closing phrase added there — the script raises rather than silently mis-chunking if no marker matches.
- **`VERSION` is the effective date, not a real revision counter.** Fine for a first ingestion of a document; if RBI reissues/amends this Direction later, a real versioning scheme (and `SUPERSEDES_CHUNK_ID` wiring) is needed before re-ingesting.
- **No page numbers**, since the source is scraped HTML, not a PDF (see `architecture.md`'s note that Cortex Search needs `PARSE_DOCUMENT` upstream for actual PDFs — that path would produce real page numbers where this one can't).
