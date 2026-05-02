#!/usr/bin/env python3
"""
md-one-sentence-per-line.py

Reformat markdown so each sentence in a paragraph sits on its own line.
CommonMark renders a single newline as a space, so the rendered HTML is
unchanged — but `git diff` becomes per-sentence and review is surgical.

Skipped (passed through unchanged):
- Frontmatter (+++ ... +++ or --- ... ---)
- Fenced code blocks (``` and ~~~)
- Indented code blocks (4-space / tab)
- Headings, horizontal rules, tables
- Hugo / Goldmark shortcodes ({{< name >}} ... {{< /name >}})
- HTML comments (single- and multi-line)

Reformatted:
- Plain paragraphs (consecutive prose lines collapsed, then split on sentences)
- Blockquotes (`> ` prefix preserved per output line)
- List items (marker preserved; continuation sentences indented under it)

Usage:
    md-one-sentence-per-line.py FILE [FILE ...]
    md-one-sentence-per-line.py --diff FILE     # preview, do not write
    md-one-sentence-per-line.py --check FILE    # exit 1 if changes pending
"""

import argparse
import re
import sys
from pathlib import Path

# Words that end with `.` but are NOT sentence boundaries.
ABBR = {
    "mr", "mrs", "ms", "dr", "prof", "sr", "jr",
    "inc", "ltd", "co", "corp", "llc",
    "e.g", "i.e", "etc", "vs", "cf", "al",
    "fig", "eq", "no", "vol", "pp", "ch",
    "st", "ave", "blvd", "rd",
    "jan", "feb", "mar", "apr", "jun", "jul",
    "aug", "sep", "sept", "oct", "nov", "dec",
    "mon", "tue", "wed", "thu", "fri", "sat", "sun",
    "a.m", "p.m", "p.s",
}

# Patterns whose contents must NOT be touched by sentence splitting.
# Order matters: protect outer-most containers first so anything nested
# inside them (e.g. inline code inside a link) is hidden by the wrapper
# rather than getting its own placeholder.
PROTECT_PATTERNS = [
    re.compile(r"<!--.*?-->", re.DOTALL),      # HTML comment
    re.compile(r"\{\{[<%].*?[%>]\}\}"),        # Hugo shortcode (inline)
    re.compile(r"!\[[^\]]*\]\([^)]+\)"),       # image
    re.compile(r"\[[^\]]*\]\([^)]+\)"),        # link
    re.compile(r"`[^`\n]*`"),                  # inline code
    re.compile(r"<[^>\n]+>"),                  # inline HTML tag
]

# A sentence boundary: terminator + optional closing brackets/quotes/emphasis,
# followed by whitespace, followed by a likely sentence start (capital, digit,
# or an opening quote/bracket/emphasis around a capital).
SENTENCE_SPLIT = re.compile(
    r"""
    ([.!?])                # 1: terminator
    (["')\]\*_`]*)         # 2: optional closing
    [ \t]+                 # whitespace (paragraphs are pre-joined with spaces)
    (?=                    # next sentence opener:
        ["'(\[\*_`<]*      #   optional opening quote/bracket/emphasis
        [A-Z0-9\x00]       #   capital, digit, or a protected span (placeholder)
    )
    """,
    re.VERBOSE,
)

# Block-detection patterns
HEADING        = re.compile(r"^\s{0,3}#{1,6}\s")
TABLE_ROW      = re.compile(r"^\s*\|")
HR             = re.compile(r"^\s{0,3}([-*_])(\s*\1){2,}\s*$")
LIST_ITEM      = re.compile(r"^(\s*)([-*+]|\d+[.)])(\s+)")
BLOCKQUOTE     = re.compile(r"^(\s*>+\s?)")
INDENTED_CODE  = re.compile(r"^( {4,}|\t)")
SHORTCODE_OPEN = re.compile(r"^\s*\{\{[<%]\s*(/?)(\w+)")


def protect(text):
    """Replace untouchable spans with NUL-delimited placeholders."""
    placeholders = []

    def stash(m):
        placeholders.append(m.group(0))
        return f"\x00{len(placeholders) - 1}\x00"

    for pat in PROTECT_PATTERNS:
        text = pat.sub(stash, text)
    return text, placeholders


def restore(text, placeholders):
    pat = re.compile(r"\x00(\d+)\x00")
    while pat.search(text):
        text = pat.sub(lambda m: placeholders[int(m.group(1))], text)
    return text


def is_abbrev_at(text, period_pos):
    """Is text[period_pos] a `.` that belongs to a known abbreviation?"""
    i = period_pos - 1
    while i >= 0 and not text[i].isspace() and text[i] not in "([{\"'":
        i -= 1
    word = text[i + 1:period_pos].lower()
    return word in ABBR


def split_sentences(text):
    """Split a single (joined) prose string into sentences."""
    if not text.strip():
        return []
    protected, placeholders = protect(text)

    cuts = []
    for m in SENTENCE_SPLIT.finditer(protected):
        if m.group(1) == "." and is_abbrev_at(protected, m.start()):
            continue
        cuts.append(m.end())

    if not cuts:
        return [restore(protected, placeholders).strip()]

    parts, prev = [], 0
    for c in cuts:
        parts.append(protected[prev:c].rstrip())
        prev = c
    parts.append(protected[prev:].rstrip())

    return [restore(p, placeholders) for p in parts if p.strip()]


def is_block_break(line):
    """Lines that always end a prose paragraph."""
    s = line.lstrip()
    return (
        line.strip() == ""
        or HEADING.match(line)
        or HR.match(line)
        or TABLE_ROW.match(line)
        or INDENTED_CODE.match(line)
        or BLOCKQUOTE.match(line)
        or LIST_ITEM.match(line)
        or s.startswith("```")
        or s.startswith("~~~")
        or s.startswith("<!--")
        or SHORTCODE_OPEN.match(line)
    )


def process(content):
    lines = content.split("\n")
    out, i = [], 0

    # Pass through frontmatter unchanged.
    if lines and lines[0].strip() in ("+++", "---"):
        marker = lines[0].strip()
        out.append(lines[0])
        i = 1
        while i < len(lines):
            out.append(lines[i])
            if lines[i].strip() == marker:
                i += 1
                break
            i += 1

    while i < len(lines):
        line = lines[i]
        s = line.lstrip()

        # Fenced code block — pass through verbatim.
        if s.startswith("```") or s.startswith("~~~"):
            fence = "```" if s.startswith("```") else "~~~"
            out.append(line)
            i += 1
            while i < len(lines):
                out.append(lines[i])
                if lines[i].lstrip().startswith(fence):
                    i += 1
                    break
                i += 1
            continue

        # Hugo shortcode — preserve as-is across opener/body/closer.
        m = SHORTCODE_OPEN.match(line)
        if m and not m.group(1):
            name = m.group(2)
            close_pat = re.compile(
                rf"\{{\{{[<%]\s*/{re.escape(name)}\s*[%>]\}}\}}"
            )
            out.append(line)
            if close_pat.search(line):
                i += 1
                continue
            i += 1
            while i < len(lines):
                out.append(lines[i])
                if close_pat.search(lines[i]):
                    i += 1
                    break
                i += 1
            continue

        # HTML comment — pass through (single- or multi-line).
        if s.startswith("<!--"):
            out.append(line)
            if "-->" in line:
                i += 1
                continue
            i += 1
            while i < len(lines):
                out.append(lines[i])
                if "-->" in lines[i]:
                    i += 1
                    break
                i += 1
            continue

        # Pass-through atoms.
        if (line.strip() == ""
                or HEADING.match(line)
                or HR.match(line)
                or TABLE_ROW.match(line)
                or INDENTED_CODE.match(line)):
            out.append(line)
            i += 1
            continue

        # Blockquote — collapse consecutive `>`-prefixed lines, split, reprefix.
        if BLOCKQUOTE.match(line):
            block = []
            while i < len(lines) and BLOCKQUOTE.match(lines[i]):
                block.append(lines[i])
                i += 1
            prefix = BLOCKQUOTE.match(block[0]).group(1)
            stripped = [BLOCKQUOTE.sub("", b).strip() for b in block]
            joined = " ".join(p for p in stripped if p)
            sentences = split_sentences(joined) or [joined]
            for sent in sentences:
                out.append(prefix + sent)
            continue

        # List item — preserve marker; subsequent sentences indent under it.
        lm = LIST_ITEM.match(line)
        if lm:
            indent, marker, spaces = lm.group(1), lm.group(2), lm.group(3)
            head = len(indent) + len(marker) + len(spaces)
            cont_indent = " " * head
            body = [line[head:]]
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if nxt.strip() == "" or LIST_ITEM.match(nxt):
                    break
                if not nxt.startswith(cont_indent):
                    break
                body.append(nxt[head:])
                i += 1
            joined = " ".join(b.strip() for b in body if b.strip())
            sentences = split_sentences(joined) or [joined]
            out.append(indent + marker + spaces + sentences[0])
            for sent in sentences[1:]:
                out.append(cont_indent + sent)
            continue

        # Plain paragraph — collect, join with spaces, split into sentences.
        para = [line]
        i += 1
        while i < len(lines) and not is_block_break(lines[i]):
            para.append(lines[i])
            i += 1
        joined = " ".join(p.strip() for p in para)
        sentences = split_sentences(joined) or [joined]
        out.extend(sentences)

    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(
        description="Reformat markdown so each sentence sits on its own line."
    )
    ap.add_argument("files", nargs="+", help="markdown files to process")
    ap.add_argument("--diff", action="store_true",
                    help="print unified diff to stdout; do not write")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if any file would change; do not write")
    args = ap.parse_args()

    changed = []
    for path in args.files:
        p = Path(path)
        original = p.read_text()
        new = process(original)
        if new == original:
            continue
        changed.append(p)
        if args.check:
            print(f"would reformat: {p}", file=sys.stderr)
        elif args.diff:
            import difflib
            sys.stdout.writelines(difflib.unified_diff(
                original.splitlines(keepends=True),
                new.splitlines(keepends=True),
                fromfile=str(p), tofile=str(p),
            ))
        else:
            p.write_text(new)
            print(f"reformatted: {p}")

    if args.check and changed:
        sys.exit(1)


if __name__ == "__main__":
    main()
