#!/usr/bin/env python3
"""Sync Readwise highlights and Reader documents into a second-brain vault's raw/ folder.

Emits Obsidian-Web-Clipper-compatible markdown files so /second-brain-ingest
treats them identically to clipped articles. Incremental (durable cursors),
idempotent (hash-gated writes), stdlib-only; the sole external dependency is
the `readwise` CLI (invoked via subprocess with --json).

Contract with the ingest skill: a raw file counts as ingested iff its exact
filename appears in wiki/log.md backticked on a `Processed:` line (new style)
or double-quoted (legacy style). This script uses the same two patterns to
classify writes as NEW vs UPDATED and to reconcile the pending-reingest ledger.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from datetime import date, datetime, timezone
from pathlib import Path

DEFAULT_VAULT = "~/Documents/sanket-wiki"
DEFAULT_STATE_DIR = "~/.local/state/readwise-second-brain-sync"
DOC_LOCATIONS = ["archive", "later"]
INBOX_LOCATION = "new"
# 'id' is always included by the CLI and is not a valid response-field value.
DOC_LIST_FIELDS = (
    "title,author,category,summary,tags,source_url,"
    "published_date,saved_at,updated_at"
)
HL_FIELDS = (
    "text,note,tags,highlighted_at,updated,url,color,book_id,"
    "book_title,book_author,book_category,book_source_url"
)
STATE_VERSION = 1


class SyncError(Exception):
    """A readwise CLI call failed after retry."""


# ---------------------------------------------------------------- CLI calls


def run_cli(args, retries=1, backoff=5):
    """Run a readwise CLI command with --json and return parsed output."""
    cmd = ["readwise"] + args + ["--json"]
    for attempt in range(retries + 1):
        try:
            proc = subprocess.run(
                cmd, capture_output=True, text=True, timeout=180
            )
            if proc.returncode == 0:
                return json.loads(proc.stdout)
            err = proc.stderr.strip() or proc.stdout.strip()
        except (subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
            err = str(exc)
        if attempt < retries:
            time.sleep(backoff)
    raise SyncError(f"readwise {' '.join(args)}: {err[:500]}")


def list_documents(location, cursor, log):
    """Yield document metadata dicts for one Reader location."""
    page_cursor = None
    while True:
        args = [
            "reader-list-documents",
            "--location", location,
            "--response-fields", DOC_LIST_FIELDS,
        ]
        if cursor:
            args += ["--updated-after", cursor]
        if page_cursor:
            args += ["--page-cursor", page_cursor]
        data = run_cli(args)
        results = data.get("results") or []
        yield from results
        page_cursor = data.get("nextPageCursor")
        if not page_cursor or not results:
            break
        log(f"  … paging {location} ({len(results)} docs)")


def get_document_content(doc_id):
    data = run_cli(["reader-get-document-details", "--document-id", doc_id])
    return data.get("content") or ""


def list_highlights(cursor, log):
    """Yield highlight dicts updated after the cursor, across all pages."""
    page = 1
    while True:
        args = [
            "readwise-list-highlights",
            "--page-size", "100",
            "--page", str(page),
            "--response-fields", HL_FIELDS,
        ]
        if cursor:
            args += ["--updated-gt", cursor]
        data = run_cli(args)
        results = data.get("results") or []
        yield from results
        if len(results) < 100:
            break
        page += 1
        log(f"  … paging highlights (page {page})")


def book_highlights(book_id):
    """Fetch ALL highlights for one book (for whole-digest regeneration)."""
    out, page = [], 1
    while True:
        data = run_cli([
            "readwise-list-highlights",
            "--book-id", str(book_id),
            "--page-size", "100",
            "--page", str(page),
            "--response-fields", HL_FIELDS,
        ])
        results = data.get("results") or []
        out.extend(results)
        if len(results) < 100:
            break
        page += 1
    return out


# ---------------------------------------------------------------- rendering


def slugify(title, max_len=60):
    value = unicodedata.normalize("NFKD", title or "")
    value = value.encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^\w\s-]", "", value).strip().lower()
    value = re.sub(r"[-\s]+", "-", value).strip("-")
    return (value[:max_len].rstrip("-")) or "untitled"


def yaml_str(value):
    """Quote a scalar for YAML frontmatter, clipper-style."""
    value = re.sub(r"\s+", " ", str(value or "")).strip()
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def is_junk_author(author, source_url=""):
    """True when an author value must not become a wikilink/entity."""
    a = (author or "").strip()
    if not a:
        return True
    if a.isdigit():
        return True
    if len(a) > 60:
        return True
    if not re.search(r"[A-Za-z]", a):
        return True
    if "." in a and " " not in a:  # bare domain like dev.to / awslabs.github.io
        return True
    host = re.sub(r"^https?://(www\.)?", "", source_url or "").split("/")[0]
    if host and a.lower() == host.lower():
        return True
    return False


def frontmatter_lines(meta, tags, created, updated=None):
    """Build clipper-parity frontmatter lines. Volatile lines flagged for hashing."""
    author = (meta.get("author") or "").strip()
    source_url = meta.get("source_url") or ""
    lines = [
        "---",
        f"title: {yaml_str(meta.get('title') or 'Untitled')}",
        f"source: {yaml_str(source_url)}",
    ]
    if is_junk_author(author, source_url):
        display = author or (re.sub(r"^https?://(www\.)?", "", source_url).split("/")[0] if source_url else "")
        lines.append(f"author: {yaml_str(display)}")
    else:
        lines.append("author:")
        lines.append(f'  - "[[{author}]]"')
    published = meta.get("published_date") or ""
    lines.append(f"published: {published}")
    lines.append(f"created: {created}")  # volatile
    if updated:
        lines.append(f"updated: {updated}")  # volatile
    lines.append(f"description: {yaml_str(meta.get('summary') or '')}")
    lines.append("tags:")
    for t in tags:
        lines.append(f'  - "{t}"')
    lines.append("---")
    return lines


def manual_tags(meta):
    """Extract manual Reader tag slugs from the tags object/list."""
    tags = meta.get("tags")
    if isinstance(tags, dict):
        return sorted(tags.keys())
    if isinstance(tags, list):
        return sorted(str(t) for t in tags)
    return []


def render_document(meta, content, created, updated=None):
    tags = ["clippings", "readwise"] + manual_tags(meta)
    lines = frontmatter_lines(meta, tags, created, updated)
    body = (content or "").strip()
    if not body:
        # Videos/podcasts/etc. with no scraped text still get a stub body.
        body = (meta.get("summary") or "").strip()
        if meta.get("source_url"):
            body += f"\n\n[Source]({meta['source_url']})"
    return "\n".join(lines) + "\n" + body.strip() + "\n"


def render_digest(book, highlights, created, updated=None):
    meta = {
        "title": f"Highlights: {book['title']}",
        "author": book.get("author") or "",
        "source_url": book.get("source_url") or "",
        "summary": (
            f"{len(highlights)} highlights from "
            f"{book.get('category') or 'source'} '{book['title']}'"
        ),
        "published_date": "",
        "tags": {},
    }
    tags = ["clippings", "readwise", "readwise-highlights"]
    lines = frontmatter_lines(meta, tags, created, updated)
    body = [f"# Highlights: {book['title']}", ""]
    info = []
    if book.get("source_url"):
        info.append(f"**Source:** {book['source_url']}")
    if book.get("author"):
        if is_junk_author(book["author"], book.get("source_url", "")):
            info.append(f"**Author:** {book['author']}")
        else:
            info.append(f"**Author:** [[{book['author']}]]")
    if book.get("category"):
        info.append(f"**Category:** {book['category']}")
    if info:
        body.append("  ·  ".join(info))
        body.append("")
    hls = sorted(highlights, key=lambda h: h.get("highlighted_at") or "")
    for i, h in enumerate(hls):
        if i:
            body.append("---")
            body.append("")
        text = (h.get("text") or "").strip()
        for ln in text.splitlines():
            body.append(f"> {ln}".rstrip())
        when = (h.get("highlighted_at") or "")[:10]
        if when:
            body.append(">")
            body.append(f"> — highlighted {when}")
        body.append("")
        note = (h.get("note") or "").strip()
        if note:
            body.append(f"**Note:** {note}")
            body.append("")
    return "\n".join(lines) + "\n" + "\n".join(body).rstrip() + "\n"


def content_hash(rendered):
    """Hash the canonical payload, excluding volatile created/updated lines."""
    keep = [
        ln for ln in rendered.splitlines()
        if not re.match(r"^(created|updated): ", ln)
    ]
    return "sha256:" + hashlib.sha256("\n".join(keep).encode()).hexdigest()


# ---------------------------------------------------------------- log.md


def parse_log(vault):
    """Map each raw filename recorded in wiki/log.md to its latest entry date."""
    log_path = vault / "wiki" / "log.md"
    ingested = {}
    current_date = ""
    if not log_path.exists():
        return ingested
    for line in log_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^## \[(\d{4}-\d{2}-\d{2})\]", line)
        if m:
            current_date = m.group(1)
            continue
        for fname in re.findall(r'`([^`]+\.md)`|"([^"]+\.md)"', line):
            name = (fname[0] or fname[1]).split("/")[-1]
            if name and (name not in ingested or current_date > ingested[name]):
                ingested[name] = current_date
    return ingested


# ---------------------------------------------------------------- state


def load_state(state_path):
    if state_path.exists():
        state = json.loads(state_path.read_text(encoding="utf-8"))
        if state.get("version") != STATE_VERSION:
            raise SyncError(
                f"state file version {state.get('version')} unsupported; "
                f"delete {state_path} and re-run with --full"
            )
        return state
    return {
        "version": STATE_VERSION,
        "cursors": {"reader_docs": None, "highlights": None},
        "documents": {},
        "highlight_books": {},
        "pending_reingest": [],
    }


def atomic_write(path, text):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def norm_ts(ts):
    """Normalize a server timestamp to sortable UTC ISO."""
    if not ts:
        return None
    try:
        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).isoformat()
    except ValueError:
        return None


def mint_filename(raw_dir, registry, key, base_name):
    """Return the recorded filename for key, or mint a unique new one."""
    if key in registry and registry[key].get("file"):
        return registry[key]["file"]
    taken = {v.get("file") for v in registry.values()}
    name = base_name
    n = 2
    while name in taken or (raw_dir / name).exists():
        stem, ext = os.path.splitext(base_name)
        name = f"{stem}-{n}{ext}"
        n += 1
    return name


# ---------------------------------------------------------------- sync core


def write_file(raw_dir, fname, rendered, results, ingested, today, state, dry):
    """Hash-gate and write one raw file; classify NEW/UPDATED; update ledger."""
    path = raw_dir / fname
    new_hash = content_hash(rendered)
    if not dry:
        atomic_write(path, rendered)
    if fname in ingested:
        results["updated"].append(fname)
        pend = state["pending_reingest"]
        if not any(p["file"] == fname for p in pend):
            pend.append({"file": fname, "changed": today, "reason": "content updated"})
    else:
        results["new"].append(fname)
    return new_hash


def sync_documents(args, state, raw_dir, ingested, today, results, log):
    cursor = None if args.full else state["cursors"]["reader_docs"]
    locations = list(DOC_LOCATIONS) + ([INBOX_LOCATION] if args.include_inbox else [])
    docs = []
    for loc in locations:
        log(f"Listing Reader docs: {loc}" + (f" (since {cursor})" if cursor else " (full)"))
        docs.extend(list_documents(loc, cursor, log))
    if args.limit:
        docs = docs[: args.limit]
    max_ts = state["cursors"]["reader_docs"]
    for meta in docs:
        doc_id = meta["id"]
        entry = state["documents"].get(doc_id, {})
        ts = norm_ts(meta.get("updated_at") or meta.get("saved_at"))
        if ts and (not max_ts or ts > max_ts):
            max_ts = ts
        fname = mint_filename(
            raw_dir, state["documents"], doc_id,
            f"{slugify(meta.get('title'))}-{doc_id[:8]}.md",
        )
        content = get_document_content(doc_id)
        created = entry.get("created") or today
        updated = today if entry else None
        rendered = render_document(meta, content, created, updated)
        new_hash = content_hash(rendered)
        if entry.get("content_hash") == new_hash:
            results["unchanged"] += 1
            continue
        new_hash = write_file(raw_dir, fname, rendered, results, ingested, today, state, args.dry_run)
        if not args.dry_run:
            state["documents"][doc_id] = {
                "file": fname,
                "created": created,
                "updated_at": ts,
                "content_hash": new_hash,
            }
    if not args.dry_run and not args.limit:
        state["cursors"]["reader_docs"] = max_ts
    log(f"Docs: {len(docs)} fetched")


def sync_highlights(args, state, raw_dir, ingested, today, results, log):
    cursor = None if args.full else state["cursors"]["highlights"]
    log("Listing highlights" + (f" (since {cursor})" if cursor else " (full)"))
    changed = {}
    max_ts = state["cursors"]["highlights"]
    for h in list_highlights(cursor, log):
        ts = norm_ts(h.get("updated") or h.get("highlighted_at"))
        if ts and (not max_ts or ts > max_ts):
            max_ts = ts
        bid = h.get("book_id")
        if bid is None:
            continue
        bid = str(bid)
        if bid not in changed:
            changed[bid] = {
                "title": h.get("book_title") or f"Book {bid}",
                "author": h.get("book_author") or "",
                "category": h.get("book_category") or "",
                "source_url": h.get("book_source_url") or "",
            }
    books = list(changed.items())
    if args.limit:
        books = books[: args.limit]
    log(f"Highlights: {len(books)} source(s) with new/changed highlights")
    for bid, book in books:
        hls = book_highlights(bid)
        if not hls:
            continue
        entry = state["highlight_books"].get(bid, {})
        fname = mint_filename(
            raw_dir, state["highlight_books"], bid,
            f"{slugify(book['title'])}-highlights-{bid}.md",
        )
        created = entry.get("created") or today
        updated = today if entry else None
        rendered = render_digest(book, hls, created, updated)
        new_hash = content_hash(rendered)
        if entry.get("content_hash") == new_hash:
            results["unchanged"] += 1
            continue
        new_hash = write_file(raw_dir, fname, rendered, results, ingested, today, state, args.dry_run)
        if not args.dry_run:
            state["highlight_books"][bid] = {
                "file": fname,
                "created": created,
                "highlight_count": len(hls),
                "content_hash": new_hash,
            }
    if not args.dry_run and not args.limit:
        state["cursors"]["highlights"] = max_ts


def reconcile_pending(state, ingested):
    """Drop pending entries whose file has an ingest log entry on/after the change date."""
    kept = []
    for p in state["pending_reingest"]:
        logged = ingested.get(p["file"])
        if logged and logged >= p["changed"]:
            continue
        kept.append(p)
    state["pending_reingest"] = kept


# ---------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", default=os.environ.get("READWISE_SYNC_VAULT", DEFAULT_VAULT))
    ap.add_argument("--full", action="store_true", help="ignore cursors, re-fetch everything")
    ap.add_argument("--include-inbox", action="store_true", help="also sync unread inbox (location 'new')")
    ap.add_argument("--dry-run", action="store_true", help="fetch and report, write nothing")
    ap.add_argument("--limit", type=int, help="cap docs and highlight-books processed (testing); cursors are not advanced")
    ap.add_argument("--docs-only", action="store_true")
    ap.add_argument("--highlights-only", action="store_true")
    ap.add_argument("--state-dir", default=os.environ.get("READWISE_SYNC_STATE_DIR", DEFAULT_STATE_DIR))
    args = ap.parse_args()

    vault = Path(args.vault).expanduser()
    raw_dir = vault / "raw"
    if not raw_dir.is_dir() or not (vault / "wiki" / "log.md").exists():
        sys.exit(f"error: {vault} does not look like a second-brain vault (need raw/ and wiki/log.md)")

    state_dir = Path(args.state_dir).expanduser()
    state_path = state_dir / "state.json"
    state = load_state(state_path)
    ingested = parse_log(vault)
    today = date.today().isoformat()
    results = {"new": [], "updated": [], "unchanged": 0}
    log = lambda msg: print(msg, file=sys.stderr)

    failures = []
    streams = []
    if not args.highlights_only:
        streams.append(("reader docs", sync_documents))
    if not args.docs_only:
        streams.append(("highlights", sync_highlights))
    for name, fn in streams:
        try:
            fn(args, state, raw_dir, ingested, today, results, log)
        except SyncError as exc:
            failures.append(f"{name}: {exc}")
            log(f"STREAM FAILED ({name}) — cursor not advanced: {exc}")

    reconcile_pending(state, ingested)
    if not args.dry_run:
        state_dir.mkdir(parents=True, exist_ok=True)
        atomic_write(state_path, json.dumps(state, indent=2) + "\n")

    # ---- report (stdout)
    mode = "DRY-RUN — nothing written" if args.dry_run else "sync complete"
    print(f"Readwise → second-brain {mode} (vault: {vault})")
    print(f"  new: {len(results['new'])}  updated: {len(results['updated'])}  unchanged: {results['unchanged']}")
    if results["new"]:
        print(f"\nNEW ({len(results['new'])}) → run /second-brain-ingest (auto-detected):")
        for f in results["new"]:
            print(f"  raw/{f}")
    if results["updated"]:
        print(f"\nUPDATED ({len(results['updated'])}) → run /second-brain-ingest and NAME these files explicitly:")
        for f in results["updated"]:
            print(f"  raw/{f}")
    carried = [p for p in state["pending_reingest"] if p["file"] not in results["updated"]]
    if carried:
        print(f"\nPending re-ingest carried from earlier runs ({len(carried)}):")
        for p in carried:
            print(f"  raw/{p['file']} (changed {p['changed']}, {p['reason']})")
    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  {f}")
        sys.exit(1)


if __name__ == "__main__":
    main()
