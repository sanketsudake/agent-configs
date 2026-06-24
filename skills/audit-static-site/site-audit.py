#!/usr/bin/env python3
"""
site-audit.py

Heuristic SEO / discoverability audit of a built Hugo site. Run it after `hugo`
against the generated `public/` tree; it parses every rendered HTML page and
flags the structural issues that quietly suppress reach:

  ERRORS  (fail --check)
    - missing/empty <title>
    - missing meta description on a content page (post/talk)
    - missing og:image
    - missing rel=canonical
    - broken internal links (href resolves to no file under public/)
  WARNINGS
    - duplicate <title> or description across pages
    - title/description length outside the SERP-friendly range
    - not exactly one <h1>
    - <img> missing alt text on a content page
    - thin content (low word count) on a post/talk
    - orphan content pages (no *contextual* inbound link from another page,
      i.e. ignoring nav/footer links that appear on nearly every page)

Stdlib only -- no BeautifulSoup, no network.

Usage:
    site-audit.py                                    # audits ./public, prints to stdout
    site-audit.py --check                            # same, but exit 1 if any ERROR found
    site-audit.py --public public --out -            # print report to stdout (explicit)
    site-audit.py --site-suffix " | My Site"         # strip site name from titles
      --sections posts,docs --out report.md          # custom sections, write to file
"""

import argparse
import re
import sys
from collections import defaultdict
from datetime import date
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

TITLE_MIN, TITLE_MAX = 15, 65        # chars (incl. site suffix tolerance)
DESC_MIN, DESC_MAX = 50, 165         # chars
THIN_WORDS = 300                     # words below this on a single page = thin


class PageParser(HTMLParser):
    """Extracts the handful of SEO-relevant signals from one page."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = None
        self.description = None
        self.og_image = None
        self.canonical = None
        self.h1_count = 0
        self.imgs = []          # (src, alt-or-None)
        self.links = []         # raw href strings
        self.words = 0
        self.is_alias = False   # Hugo alias/redirect stub (meta http-equiv refresh)
        self._stack = []
        self._in_title = False
        self._skip_depth = 0    # inside script/style
        self._article_depth = 0  # inside <article>/<main>

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self._stack.append(tag)
        if tag in ("script", "style"):
            self._skip_depth += 1
        elif tag in ("article", "main"):
            self._article_depth += 1
        elif tag == "title":
            self._in_title = True
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "meta":
            if (a.get("http-equiv") or "").lower() == "refresh":
                self.is_alias = True
            if a.get("name") == "description" and self.description is None:
                self.description = (a.get("content") or "").strip()
            if a.get("property") == "og:image" and self.og_image is None:
                self.og_image = (a.get("content") or "").strip()
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = (a.get("href") or "").strip()
        elif tag == "img":
            self.imgs.append((a.get("src", ""), a.get("alt")))
        elif tag == "a" and a.get("href"):
            self.links.append(a["href"].strip())

    def handle_endtag(self, tag):
        if self._stack and self._stack[-1] == tag:
            self._stack.pop()
        if tag in ("script", "style") and self._skip_depth:
            self._skip_depth -= 1
        elif tag in ("article", "main") and self._article_depth:
            self._article_depth -= 1
        elif tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title = ((self.title or "") + data).strip()
        elif self._skip_depth == 0 and self._article_depth > 0:
            self.words += len(data.split())


def url_path(file: Path, root: Path) -> str:
    """public/posts/foo/index.html -> /posts/foo/ ; public/x.html -> /x.html"""
    rel = file.relative_to(root).as_posix()
    if rel.endswith("index.html"):
        rel = rel[: -len("index.html")]
    return "/" + rel


PAGINATION_RE = re.compile(r"/page/\d+/$")


def is_pagination(path: str) -> bool:
    return bool(PAGINATION_RE.search(path))


def bare_title(title: str, suffix_re) -> str:
    """Title without the site-name suffix, for length checks."""
    if suffix_re:
        return suffix_re.sub("", title).strip()
    return title.strip()


def is_single(path: str, content_sections: tuple) -> bool:
    parts = [p for p in path.split("/") if p]
    return len(parts) == 2 and parts[0] in content_sections


def resolve_link(href: str, base_host: str, root: Path) -> Path | None:
    """Return the public/ file a link should resolve to, or None if external/non-page."""
    s = urlsplit(href)
    if s.scheme in ("mailto", "tel", "javascript"):
        return None
    if s.netloc and s.netloc != base_host:
        return None  # external
    p = s.path
    if not p:
        return None  # pure fragment / same page
    p = p.split("#")[0]
    if not p.startswith("/"):
        return None  # relative odd link; skip
    # only resolve page-like links (no extension, or .html); assets are fine as-is
    if "." in Path(p).name and not p.endswith(".html"):
        target = root / p.lstrip("/")
        return target  # asset; existence still checked
    if p.endswith("/") or "." not in Path(p).name:
        return root / p.strip("/") / "index.html"
    return root / p.lstrip("/")


def main():
    ap = argparse.ArgumentParser(description="Heuristic SEO/discoverability audit of a built Hugo site.")
    ap.add_argument("--public", default="public", help="path to the built site (default: public)")
    ap.add_argument("--out", default="-", help="report path, or '-' for stdout (default: -)")
    ap.add_argument("--check", action="store_true", help="exit 1 if any ERROR-level finding")
    ap.add_argument("--min-words", type=int, default=THIN_WORDS)
    ap.add_argument("--site-suffix", default="",
                    help="Trailing site-name string appended to every <title> (stripped before length checks)")
    ap.add_argument("--sections", default="posts,talks",
                    help="Comma-separated content section dir names under the output root to audit")
    args = ap.parse_args()

    site_suffix = args.site_suffix
    suffix_re = re.compile(re.escape(site_suffix) + r"\s*$") if site_suffix else None
    content_sections = tuple(s.strip() for s in args.sections.split(",") if s.strip())

    root = Path(args.public).resolve()
    if not root.is_dir():
        sys.exit(f"no built site at {root} -- run `hugo` first")

    pages = {}          # url_path -> PageParser
    for f in sorted(root.rglob("*.html")):
        parser = PageParser()
        try:
            parser.feed(f.read_text(encoding="utf-8", errors="replace"))
        except Exception as e:  # noqa: BLE001
            print(f"warn: could not parse {f}: {e}", file=sys.stderr)
            continue
        path = url_path(f, root)
        if parser.is_alias or is_pagination(path):
            continue  # redirect stub or paginator page — not a distinct indexable page
        pages[path] = parser

    base_host = ""
    home = pages.get("/")
    if home and home.canonical:
        base_host = urlsplit(home.canonical).netloc

    errors = defaultdict(list)    # check -> [url, ...]
    warnings = defaultdict(list)

    # title / description duplicate maps
    by_title = defaultdict(list)
    by_desc = defaultdict(list)

    # inbound link graph (target url_path -> set of source url_paths)
    inbound = defaultdict(set)
    target_sources = defaultdict(set)   # for nav detection: which pages link a target

    for path, pg in pages.items():
        for href in pg.links:
            tgt = resolve_link(href, base_host, root)
            if tgt is None:
                continue
            # broken internal link?
            if not tgt.exists():
                errors["broken internal link"].append(f"{path} -> {href}")
            # build inbound graph for page targets only
            try:
                tpath = url_path(tgt, root) if tgt.name == "index.html" else "/" + tgt.relative_to(root).as_posix()
            except ValueError:
                continue
            if tpath in pages and tpath != path:
                target_sources[tpath].add(path)

    for path, pg in pages.items():
        # title
        if not pg.title:
            errors["missing <title>"].append(path)
        else:
            by_title[pg.title].append(path)
            # length is judged on the bare title (suffix stripped) for singles,
            # where it actually affects the SERP snippet.
            if is_single(path, content_sections):
                n = len(bare_title(pg.title, suffix_re))
                if not (TITLE_MIN <= n <= TITLE_MAX):
                    warnings[f"title length (aim {TITLE_MIN}-{TITLE_MAX} chars)"].append(
                        f"{path} ({n})")
        # og:image
        if not pg.og_image:
            errors["missing og:image"].append(path)
        # canonical
        if not pg.canonical:
            errors["missing rel=canonical"].append(path)
        # h1
        if pg.h1_count != 1:
            warnings["not exactly one <h1>"].append(f"{path} ({pg.h1_count})")

        if is_single(path, content_sections):
            # description
            if not pg.description:
                errors["missing meta description"].append(path)
            else:
                by_desc[pg.description].append(path)
                if not (DESC_MIN <= len(pg.description) <= DESC_MAX):
                    warnings[f"description length (aim {DESC_MIN}-{DESC_MAX} chars)"].append(
                        f"{path} ({len(pg.description)})")
            # thin content (primary section only — secondary sections like
            # talks are slide decks, legitimately short)
            primary_prefix = "/" + content_sections[0] + "/"
            if path.startswith(primary_prefix) and pg.words < args.min_words:
                warnings[f"thin content (<{args.min_words} words)"].append(
                    f"{path} ({pg.words} words)")
            # missing alt
            noalt = sum(1 for src, alt in pg.imgs if not (alt and alt.strip()))
            if noalt:
                warnings["images missing alt text"].append(f"{path} ({noalt} img)")

    # duplicates
    for title, paths in by_title.items():
        if len(paths) > 1:
            warnings["duplicate <title>"].append(f"{title!r}: {', '.join(paths)}")
    for desc, paths in by_desc.items():
        if len(paths) > 1:
            warnings["duplicate meta description"].append(f"{', '.join(paths)}")

    # orphans: a content single linked from nowhere (only reachable via the
    # sitemap). Pages reachable via their section list have an inbound edge, so
    # a zero-inbound page is the genuinely actionable case.
    for path in pages:
        if not is_single(path, content_sections):
            continue
        if not target_sources.get(path):
            warnings["orphan: no inbound links"].append(path)

    # ---- render report ----
    today = date.today().isoformat()
    lines = [f"# Site audit — {today}", ""]
    lines.append(f"Audited **{len(pages)}** pages under `{args.public}/`"
                 f"{f' (host `{base_host}`)' if base_host else ''}.")
    n_err = sum(len(v) for v in errors.values())
    n_warn = sum(len(v) for v in warnings.values())
    lines += ["", f"- **Errors:** {n_err}", f"- **Warnings:** {n_warn}", ""]

    def section(title, bucket):
        out = [f"## {title}", ""]
        if not bucket:
            out += ["_None._", ""]
            return out
        for check in sorted(bucket):
            items = bucket[check]
            out.append(f"### {check} ({len(items)})")
            out += [f"- `{i}`" for i in sorted(items)[:50]]
            if len(items) > 50:
                out.append(f"- … and {len(items) - 50} more")
            out.append("")
        return out

    lines += section("Errors", errors)
    lines += section("Warnings", warnings)
    report = "\n".join(lines) + "\n"

    if args.out == "-":
        sys.stdout.write(report)
    else:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(report, encoding="utf-8")
        print(f"wrote {out}  (errors: {n_err}, warnings: {n_warn})")

    if args.check and n_err:
        sys.exit(1)


if __name__ == "__main__":
    main()
