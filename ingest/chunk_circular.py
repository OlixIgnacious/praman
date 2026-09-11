"""Chunk a scraped RBI Master Direction .txt file into RULE_CORPUS rows.

These circulars were extracted from RBI's website as plain text (see
notebooks/rbi_scraping.ipynb), not from a PDF, so there is no PARSE_DOCUMENT
step and no real page boundary — PAGE_NO is left NULL for this source type.
What the source text does have is RBI's own citable structure: numbered
paragraphs (1., 2., 3., ...) nested under lettered subsections (A., B., C.)
nested under Roman-numeral chapters. That numbered paragraph is the unit RBI
documents are conventionally cited by (e.g. "para 21"), so it's the chunk
grain here — SECTION_REF records the chapter/subsection/paragraph a chunk
came from so a citation can point at a specific obligation, not just "the
document."

The file layout (see data/raw/circulars/*.txt): four header lines (DOC_ID |
internal ref, title, "Issued: <date>", "Source: <url>"), a blank line, a
"---" separator, then the entire body as one line — a table of contents
followed by a preamble followed by the numbered body (headers repeat inline
before their actual content). Only the text after the preamble's closing
phrase is chunked; the TOC is pure navigation with no independent obligation
to cite.

Usage: uv run python ingest/chunk_circular.py <path/to/circular.txt> [--out data/processed/rule_corpus_chunks.csv] [--jurisdiction IN] [--append]
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from datetime import datetime
from pathlib import Path

PREAMBLE_END_MARKERS = [
    "hereby, issues Directions hereinafter specified.",
    "hereby, issue the Directions hereinafter specified.",
]

CHAPTER_RE = re.compile(r"Chapter\s+([IVXLC]+)\s*-\s*([^0-9]+?)(?=\s[A-F]\.\s[A-Z])")
SUBSECTION_RE = re.compile(r"\b([A-F])\.\s+([A-Z][^0-9]*?)(?=\s\d{1,3}\.\s+[A-Z(])")


def find_body(raw: str) -> str:
    for marker in PREAMBLE_END_MARKERS:
        idx = raw.find(marker)
        if idx != -1:
            return raw[idx + len(marker) :].strip()
    raise ValueError(
        "Could not find a known preamble-end marker — inspect the source file "
        "and add its exact closing phrase to PREAMBLE_END_MARKERS."
    )


def find_numbered_paragraphs(body: str, max_n: int = 300) -> list[tuple[int, int, int]]:
    """Sequentially locate '1. ', '2. ', '3. ', ... — RBI's own paragraph numbering.
    Sequential search (rather than one global regex) means a stray digit+period
    inside a table row can't be mistaken for the next real paragraph marker,
    since we only ever look for the *next* number in strict order."""
    positions = []
    search_from = 0
    n = 1
    while n <= max_n:
        pattern = re.compile(rf"(?<!\d){n}\.\s+(?=[A-Z(])")
        m = pattern.search(body, search_from)
        if not m:
            break
        positions.append((n, m.start(), m.end()))
        search_from = m.end()
        n += 1
    if not positions:
        raise ValueError("Found zero numbered paragraphs — check the body text/markers.")
    return positions


def build_section_map(body: str) -> tuple[list[tuple[int, str, str]], list[tuple[int, str, str]]]:
    """Returns (chapter_headers, subsection_headers) as (offset, code, title), sorted by offset."""
    chapters = [(m.start(), m.group(1), m.group(2).strip()) for m in CHAPTER_RE.finditer(body)]
    subsections = [(m.start(), m.group(1), m.group(2).strip()) for m in SUBSECTION_RE.finditer(body)]
    return chapters, subsections


def section_ref_for(offset: int, chapters: list[tuple[int, str, str]], subsections: list[tuple[int, str, str]]) -> str:
    chapter = next((c for c in reversed(chapters) if c[0] <= offset), None)
    subsection = next((s for s in reversed(subsections) if s[0] <= offset), None)
    parts = []
    if chapter:
        parts.append(f"Chapter {chapter[1]} - {chapter[2]}")
    if subsection:
        parts.append(f"{subsection[1]}. {subsection[2]}")
    return " > ".join(parts) if parts else ""


def parse_header(lines: list[str]) -> dict:
    doc_id = lines[0].split("|")[0].strip()
    doc_title = lines[1].strip()
    issued_match = re.search(r"Issued:\s*(.+)", lines[2])
    issued_raw = issued_match.group(1).strip() if issued_match else ""
    try:
        effective_date = datetime.strptime(issued_raw, "%B %d, %Y").date().isoformat()
    except ValueError:
        effective_date = ""
    return {"doc_id": doc_id, "doc_title": doc_title, "effective_date": effective_date}


def chunk_file(path: Path, jurisdiction: str) -> list[dict]:
    raw_lines = path.read_text(encoding="utf-8").splitlines()
    header = parse_header(raw_lines)
    body_line = next(l for l in raw_lines if l.strip() and not l.startswith(("RBI/", "Reserve Bank", "Issued:", "Source:", "(PDF", "---")))
    body = find_body(body_line)

    chapters, subsections = build_section_map(body)
    paragraphs = find_numbered_paragraphs(body)
    header_offsets = sorted(o for o, _, _ in chapters + subsections)

    rows = []
    for i, (n, start, _header_end) in enumerate(paragraphs):
        raw_end = paragraphs[i + 1][1] if i + 1 < len(paragraphs) else len(body)
        # A chapter/subsection header for the *next* chunk can fall inside this
        # span (it appears in the source between one paragraph's content and
        # the next paragraph's number) — trim it off so it doesn't bleed into
        # this chunk's text.
        next_header = next((o for o in header_offsets if start < o < raw_end), None)
        text_end = next_header if next_header is not None else raw_end
        chunk_text = body[start:text_end].strip()
        rows.append(
            {
                "CHUNK_ID": f"{header['doc_id']}#{n}",
                "DOC_ID": header["doc_id"],
                "DOC_TITLE": header["doc_title"],
                "JURISDICTION": jurisdiction,
                "VERSION": header["effective_date"] or "1",
                "EFFECTIVE_DATE": header["effective_date"],
                "SECTION_REF": f"{section_ref_for(start, chapters, subsections)} > para {n}".strip(" >"),
                "PAGE_NO": "",
                "CHUNK_TEXT": chunk_text,
                "SUPERSEDES_CHUNK_ID": "",
                "SOURCE_FILE": f"data/raw/circulars/{path.name}",
            }
        )
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path)
    ap.add_argument("--out", type=Path, default=Path("data/processed/rule_corpus_chunks.csv"))
    ap.add_argument("--jurisdiction", default="IN")
    ap.add_argument("--append", action="store_true", help="Append to --out instead of overwriting")
    args = ap.parse_args()

    rows = chunk_file(args.source, args.jurisdiction)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "CHUNK_ID", "DOC_ID", "DOC_TITLE", "JURISDICTION", "VERSION", "EFFECTIVE_DATE",
        "SECTION_REF", "PAGE_NO", "CHUNK_TEXT", "SUPERSEDES_CHUNK_ID", "SOURCE_FILE",
    ]
    mode = "a" if args.append and args.out.exists() else "w"
    write_header = not (args.append and args.out.exists())
    with args.out.open(mode, newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} chunks from {args.source.name} -> {args.out}", file=sys.stderr)
    for r in rows:
        print(f"  {r['CHUNK_ID']:>40}  {r['SECTION_REF']}", file=sys.stderr)


if __name__ == "__main__":
    main()
