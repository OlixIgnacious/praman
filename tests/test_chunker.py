"""Tests for the RBI circular chunker."""

import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "ingest"))

from chunk_circular import (
    build_section_map,
    chunk_file,
    find_body,
    find_numbered_paragraphs,
    parse_header,
    section_ref_for,
)

CIRCULAR_PATH = Path(__file__).parent.parent / "data" / "raw" / "circulars" / "RBI_DoS_2026-27_415_Commercial_Banks_Supervisory_Returns_Directions_2026.txt"


# --- find_body ---

def test_find_body_with_known_marker():
    text = "Some preamble hereby, issues Directions hereinafter specified. The actual body."
    result = find_body(text)
    assert result == "The actual body."


def test_find_body_alternate_marker():
    text = "Blah blah hereby, issue the Directions hereinafter specified. Body two."
    result = find_body(text)
    assert result == "Body two."


def test_find_body_raises_on_no_marker():
    with pytest.raises(ValueError, match="preamble-end marker"):
        find_body("No known marker in this text at all.")


# --- find_numbered_paragraphs ---

def test_find_numbered_paragraphs_basic():
    body = "1. Alpha content here. 2. Beta content. 3. Gamma content."
    result = find_numbered_paragraphs(body)
    assert len(result) == 3
    assert [r[0] for r in result] == [1, 2, 3]


def test_find_numbered_paragraphs_sequential():
    body = "1. First. 3. Third without second."
    result = find_numbered_paragraphs(body)
    assert len(result) == 1
    assert result[0][0] == 1


def test_find_numbered_paragraphs_raises_on_empty():
    with pytest.raises(ValueError, match="zero numbered paragraphs"):
        find_numbered_paragraphs("No paragraphs here at all.")


# --- build_section_map ---

def test_build_section_map_detects_chapters():
    body = "Chapter III - Filing of Supervisory Returns A. Scope 1. First para."
    chapters, subsections = build_section_map(body)
    assert len(chapters) == 1
    assert chapters[0][1] == "III"
    assert "Filing" in chapters[0][2]


def test_build_section_map_detects_subsections():
    body = "Chapter III - Filing of Supervisory Returns A. Scope 1. First para."
    chapters, subsections = build_section_map(body)
    assert len(subsections) == 1
    assert subsections[0][1] == "A"


# --- section_ref_for ---

def test_section_ref_for_with_chapter_and_subsection():
    chapters = [(0, "III", "Filing")]
    subsections = [(30, "A", "Scope")]
    ref = section_ref_for(50, chapters, subsections)
    assert "Chapter III - Filing" in ref
    assert "A. Scope" in ref


def test_section_ref_for_before_any_chapter():
    ref = section_ref_for(0, [], [])
    assert ref == ""


def test_section_ref_for_chapter_only():
    chapters = [(0, "I", "Title")]
    ref = section_ref_for(10, chapters, [])
    assert ref == "Chapter I - Title"


# --- parse_header ---

def test_parse_header_normal():
    lines = [
        "RBI/DoS/2026-27/415 | some internal ref",
        "Reserve Bank of India (Commercial Banks) Directions, 2026",
        "Issued: September 01, 2026",
    ]
    result = parse_header(lines)
    assert result["doc_id"] == "RBI/DoS/2026-27/415"
    assert "Commercial Banks" in result["doc_title"]
    assert result["effective_date"] == "2026-09-01"


def test_parse_header_malformed_date():
    lines = [
        "RBI/123 | ref",
        "Some Title",
        "Issued: not-a-date",
    ]
    result = parse_header(lines)
    assert result["effective_date"] == ""


# --- chunk_file end-to-end (against real circular) ---

@pytest.fixture(scope="module")
def chunks():
    if not CIRCULAR_PATH.exists():
        pytest.skip(f"Circular file not found: {CIRCULAR_PATH}")
    return chunk_file(CIRCULAR_PATH, "IN")


def test_chunk_count(chunks):
    assert len(chunks) == 30


def test_chunk_ids_well_formed(chunks):
    for c in chunks:
        assert "#" in c["CHUNK_ID"]
        doc_id, para = c["CHUNK_ID"].rsplit("#", 1)
        assert doc_id == "RBI/DoS/2026-27/415"
        assert para.isdigit()


def test_chunk_ids_sequential(chunks):
    para_nums = [int(c["CHUNK_ID"].rsplit("#", 1)[1]) for c in chunks]
    assert para_nums == list(range(1, 31))


def test_section_refs_populated(chunks):
    for c in chunks:
        assert c["SECTION_REF"], f"Empty SECTION_REF for {c['CHUNK_ID']}"
        assert "para" in c["SECTION_REF"]


def test_chunk_text_nonempty(chunks):
    for c in chunks:
        assert len(c["CHUNK_TEXT"]) > 10, f"Suspiciously short text for {c['CHUNK_ID']}"


def test_jurisdiction_set(chunks):
    for c in chunks:
        assert c["JURISDICTION"] == "IN"


def test_effective_date_populated(chunks):
    for c in chunks:
        assert c["EFFECTIVE_DATE"], f"Empty EFFECTIVE_DATE for {c['CHUNK_ID']}"


# --- boundary correctness (regression for a real bug: a subsection header
# sitting between two paragraphs in the source text was bleeding onto the
# end of the earlier paragraph's chunk instead of staying out of both) ---

def test_no_header_bleed_between_chunks(chunks):
    by_para = {int(c["CHUNK_ID"].rsplit("#", 1)[1]): c for c in chunks}
    # Para 21 -> para 22 crosses a "C. Timelines" subsection header in the
    # source ("...security measures provided. C. Timelines 22. The
    # timelines..."). That header belongs to chunk 22's SECTION_REF, not
    # chunk 21's trailing text.
    assert not by_para[21]["CHUNK_TEXT"].rstrip().endswith("Timelines")
    assert by_para[22]["CHUNK_TEXT"].startswith("22. The timelines")
    assert "C. Timelines" in by_para[22]["SECTION_REF"]


def test_no_chunk_starts_with_a_bare_header(chunks):
    # A chunk's text is the paragraph's own numbered marker onward — never a
    # leftover "B. Some Heading" fragment from the previous boundary.
    for c in chunks:
        para_num = c["CHUNK_ID"].rsplit("#", 1)[1]
        assert c["CHUNK_TEXT"].startswith(f"{para_num}. "), (
            f"{c['CHUNK_ID']} text doesn't start with its own paragraph marker: "
            f"{c['CHUNK_TEXT'][:50]!r}"
        )
