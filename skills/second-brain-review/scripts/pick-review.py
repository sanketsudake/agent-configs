#!/usr/bin/env python3
"""Pick a daily review set from a second-brain vault.

Samples highlights from source pages and summaries from concept pages,
excluding anything reviewed in the last N days (parsed from wiki/log.md
`review` entries). Seeded by date so re-runs on the same day return the
same set. Prints JSON to stdout.
"""

import argparse
import json
import os
import random
import re
import sys
from datetime import date, timedelta
from pathlib import Path

DEFAULT_VAULT = "~/Documents/sanket-wiki"


def page_title(text, fallback):
    m = re.search(r"^# (.+)$", text, re.M)
    return m.group(1).strip() if m else fallback


def recent_reviews(vault, days):
    """Titles mentioned in `review` log entries within the window."""
    log = vault / "wiki" / "log.md"
    if not log.exists():
        return set()
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    seen, current, in_window = set(), "", False
    for line in log.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^## \[(\d{4}-\d{2}-\d{2})\] (\w[\w-]*)", line)
        if m:
            current, in_window = m.group(2), m.group(1) >= cutoff
            continue
        if current == "review" and in_window:
            seen.update(re.findall(r"\[\[([^\]]+)\]\]", line))
    return seen


def collect(vault, exclude):
    highlights, concepts, stale = [], [], []
    for f in sorted((vault / "wiki" / "sources").glob("*.md")):
        text = f.read_text(encoding="utf-8")
        title = page_title(text, f.stem)
        if title in exclude:
            continue
        sect = re.search(r"^## Highlights\n(.*?)(?=^## |\Z)", text, re.M | re.S)
        if sect:
            for b in re.findall(r"^- (.+)$", sect.group(1), re.M):
                if len(b.strip()) > 40:  # skip trivial fragments
                    highlights.append({"type": "highlight", "page": title, "text": b.strip()})
        upd = re.search(r"^updated: (\d{4}-\d{2}-\d{2})", text, re.M)
        stale.append((upd.group(1) if upd else "0000", title,
                      re.sub(r"\s+", " ", (re.search(r"^## Summary\n+(.+)$", text, re.M) or [None, ""])[1])[:240]))
    for f in sorted((vault / "wiki" / "concepts").glob("*.md")):
        text = f.read_text(encoding="utf-8")
        title = page_title(text, f.stem)
        if title in exclude:
            continue
        body = re.sub(r"^---\n.*?\n---\n", "", text, flags=re.S)
        para = next((p.strip() for p in re.split(r"\n\n+", body)
                     if p.strip() and not p.strip().startswith("#")), "")
        concepts.append({"type": "concept", "page": title,
                         "text": re.sub(r"\s+", " ", para)[:400]})
    stale.sort()  # oldest updated first
    return highlights, concepts, stale


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", default=os.environ.get("READWISE_SYNC_VAULT", DEFAULT_VAULT))
    ap.add_argument("--count", type=int, default=7, help="total items to pick")
    ap.add_argument("--exclude-days", type=int, default=30,
                    help="skip pages reviewed within this many days")
    ap.add_argument("--seed", default=date.today().isoformat(),
                    help="random seed (default: today, so same-day runs match)")
    args = ap.parse_args()

    vault = Path(args.vault).expanduser()
    if not (vault / "wiki").is_dir():
        sys.exit(f"error: {vault} does not look like a second-brain vault")

    exclude = recent_reviews(vault, args.exclude_days)
    highlights, concepts, stale = collect(vault, exclude)
    rng = random.Random(args.seed)

    n_hl = max(1, round(args.count * 0.6))
    n_co = max(1, round(args.count * 0.3))
    n_st = max(0, args.count - n_hl - n_co)

    picks = []
    picks += rng.sample(highlights, min(n_hl, len(highlights)))
    picks += rng.sample(concepts, min(n_co, len(concepts)))
    # stale: oldest-updated source pages, as "haven't seen this in a while"
    for upd, title, summary in stale[: n_st]:
        picks.append({"type": "stale-source", "page": title,
                      "text": summary or "(no summary)", "last_updated": upd})
    rng.shuffle(picks)
    print(json.dumps({
        "date": date.today().isoformat(),
        "pool": {"highlights": len(highlights), "concepts": len(concepts)},
        "excluded_recent": len(exclude),
        "items": picks,
    }, indent=1))


if __name__ == "__main__":
    main()
