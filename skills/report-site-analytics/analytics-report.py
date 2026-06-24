#!/usr/bin/env python3
"""
analytics-report.py

Pull a reachability snapshot from Google Analytics 4 (on-site behaviour) and
Google Search Console (search discoverability) and write a dated report plus a
machine-readable JSON sibling that the improvement loop diffs across runs.

Each source is independent: if one isn't configured or its API call fails, the
report notes it and continues with the other. Nothing here writes to GA/GSC.

Configuration (env vars, or CLI flags, or a gitignored `.env.analytics` you
`source` first):
    GA4_PROPERTY_ID   numeric GA4 property id (Admin -> Property Settings),
                      NOT the public G-XXXX measurement id.
    GSC_SITE_URL      Search Console property, e.g. "https://example.com/" or
                      "sc-domain:example.com". Required if --site is not passed.

Auth uses Application Default Credentials. See docs/analytics/SETUP.md — the ADC
login must request the analytics + webmasters read-only scopes explicitly.

Usage:
    analytics-report.py                       # last 28 days -> stdout (set GSC_SITE_URL)
    analytics-report.py --days 90
    analytics-report.py --property 123456789 --site https://example.com/
    analytics-report.py --out -               # markdown to stdout
"""

import argparse
import json
import os
import sys
from datetime import date, timedelta
from pathlib import Path

# search opportunity thresholds
LOW_CTR = 0.02            # < 2% CTR with real impressions = title/meta opportunity
MIN_IMPRESSIONS = 50      # ignore long-tail noise below this
NEAR_MISS = (5.0, 20.0)   # avg position band where a nudge can win page-1 traffic
GSC_LAG_DAYS = 3          # GSC data is typically complete only up to ~3 days ago


def load_local_env():
    """Source KEY=VALUE lines from gitignored .env / .env.analytics, if present.
    Existing environment variables win; .env.analytics overrides .env."""
    for name in (".env", ".env.analytics"):
        f = Path(name)
        if not f.exists():
            continue
        for line in f.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


# ---------------------------------------------------------------------------
# GA4 Data API
# ---------------------------------------------------------------------------
def ga4_report(property_id: str, days: int) -> dict:
    from google.analytics.data_v1beta import BetaAnalyticsDataClient
    from google.analytics.data_v1beta.types import (
        DateRange, Dimension, Metric, RunReportRequest, OrderBy,
    )

    client = BetaAnalyticsDataClient()
    rng = [DateRange(start_date=f"{days}daysAgo", end_date="today")]
    prop = f"properties/{property_id}"

    def run(dims, mets, order_metric=None, limit=15):
        order = None
        if order_metric:
            order = [OrderBy(metric=OrderBy.MetricOrderBy(metric_name=order_metric), desc=True)]
        req = RunReportRequest(
            property=prop,
            date_ranges=rng,
            dimensions=[Dimension(name=d) for d in dims],
            metrics=[Metric(name=m) for m in mets],
            order_bys=order or [],
            limit=limit,
        )
        resp = client.run_report(req)
        rows = []
        for r in resp.rows:
            row = {d.name: v.value for d, v in zip(req.dimensions, r.dimension_values)}
            row.update({m.name: v.value for m, v in zip(req.metrics, r.metric_values)})
            rows.append(row)
        return rows

    return {
        "top_pages": run(["pagePath"], ["screenPageViews", "totalUsers", "engagementRate"],
                         order_metric="screenPageViews"),
        "channels": run(["sessionDefaultChannelGroup"], ["sessions", "totalUsers"],
                        order_metric="sessions", limit=10),
        "countries": run(["country"], ["totalUsers"], order_metric="totalUsers", limit=10),
        "new_vs_returning": run(["newVsReturning"], ["totalUsers", "sessions"], limit=5),
    }


# ---------------------------------------------------------------------------
# Search Console API
# ---------------------------------------------------------------------------
def gsc_report(site_url: str, days: int) -> dict:
    import google.auth
    from googleapiclient.discovery import build

    scopes = ["https://www.googleapis.com/auth/webmasters.readonly"]
    creds, _ = google.auth.default(scopes=scopes)
    svc = build("searchconsole", "v1", credentials=creds, cache_discovery=False)

    end = date.today() - timedelta(days=GSC_LAG_DAYS)
    start = end - timedelta(days=days)

    def query(dimensions, limit=25):
        body = {
            "startDate": start.isoformat(),
            "endDate": end.isoformat(),
            "dimensions": dimensions,
            "rowLimit": limit,
        }
        resp = svc.searchanalytics().query(siteUrl=site_url, body=body).execute()
        out = []
        for r in resp.get("rows", []):
            row = {dim: key for dim, key in zip(dimensions, r.get("keys", []))}
            row.update({
                "clicks": r.get("clicks", 0),
                "impressions": r.get("impressions", 0),
                "ctr": round(r.get("ctr", 0.0), 4),
                "position": round(r.get("position", 0.0), 1),
            })
            out.append(row)
        return out

    queries = query(["query"], limit=50)
    low_ctr = [q for q in queries
               if q["impressions"] >= MIN_IMPRESSIONS and q["ctr"] < LOW_CTR]
    near_miss = [q for q in queries
                 if NEAR_MISS[0] <= q["position"] <= NEAR_MISS[1]
                 and q["impressions"] >= MIN_IMPRESSIONS]
    return {
        "range": {"start": start.isoformat(), "end": end.isoformat()},
        "top_queries": queries[:25],
        "top_pages": query(["page"], limit=25),
        "opportunity_low_ctr": sorted(low_ctr, key=lambda q: -q["impressions"]),
        "opportunity_near_miss": sorted(near_miss, key=lambda q: -q["impressions"]),
    }


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def _table(rows, cols):
    if not rows:
        return ["_No data._", ""]
    out = ["| " + " | ".join(cols) + " |", "| " + " | ".join("---" for _ in cols) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(r.get(c, "")) for c in cols) + " |")
    out.append("")
    return out


def render(data: dict, days: int) -> str:
    L = [f"# Analytics report — {date.today().isoformat()}", "",
         f"Window: last **{days} days**. Generated by `scripts/analytics-report.py`.", ""]

    ga = data.get("ga4")
    L += ["## On-site behaviour (GA4)", ""]
    if isinstance(ga, dict):
        L += ["### Top pages", ""]
        L += _table(ga["top_pages"], ["pagePath", "screenPageViews", "totalUsers", "engagementRate"])
        L += ["### Acquisition channels", ""]
        L += _table(ga["channels"], ["sessionDefaultChannelGroup", "sessions", "totalUsers"])
        L += ["### Top countries", ""]
        L += _table(ga["countries"], ["country", "totalUsers"])
        L += ["### New vs returning", ""]
        L += _table(ga["new_vs_returning"], ["newVsReturning", "totalUsers", "sessions"])
    else:
        L += [f"> Not available: {ga}", ""]

    gsc = data.get("gsc")
    L += ["## Search discoverability (Search Console)", ""]
    if isinstance(gsc, dict):
        L += [f"Window: {gsc['range']['start']} → {gsc['range']['end']} "
              f"(GSC lags ~{GSC_LAG_DAYS} days).", ""]
        L += ["### Opportunities — high impressions, low CTR (improve title/summary/og)", ""]
        L += _table(gsc["opportunity_low_ctr"], ["query", "impressions", "ctr", "position"])
        L += ["### Opportunities — page-2 near-misses (position 5–20: strengthen content + internal links)", ""]
        L += _table(gsc["opportunity_near_miss"], ["query", "impressions", "position", "clicks"])
        L += ["### Top queries", ""]
        L += _table(gsc["top_queries"], ["query", "clicks", "impressions", "ctr", "position"])
        L += ["### Top pages", ""]
        L += _table(gsc["top_pages"], ["page", "clicks", "impressions", "ctr", "position"])
    else:
        L += [f"> Not available: {gsc}", ""]

    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description="GA4 + Search Console reachability snapshot.")
    ap.add_argument("--days", type=int, default=28)
    ap.add_argument("--property", default=None, help="GA4 numeric property id")
    ap.add_argument("--site", default=None, help="GSC site URL or sc-domain:")
    ap.add_argument("--out", default="-", help="markdown path, '-' for stdout (default: stdout)")
    args = ap.parse_args()

    load_local_env()
    property_id = args.property or os.environ.get("GA4_PROPERTY_ID")
    site_url = args.site or os.environ.get("GSC_SITE_URL")
    if not site_url:
        ap.error("--site is required (or set GSC_SITE_URL env var)")

    data = {}
    if property_id:
        try:
            data["ga4"] = ga4_report(property_id, args.days)
        except Exception as e:  # noqa: BLE001
            data["ga4"] = f"GA4 error ({type(e).__name__}): {e}"
    else:
        data["ga4"] = "GA4_PROPERTY_ID not set (see docs/analytics/SETUP.md)."

    if site_url:
        try:
            data["gsc"] = gsc_report(site_url, args.days)
        except Exception as e:  # noqa: BLE001
            data["gsc"] = f"GSC error ({type(e).__name__}): {e}"

    report = render(data, args.days)
    if args.out == "-":
        sys.stdout.write(report)
        return

    today = date.today().isoformat()
    base = Path(args.out) if args.out else Path("docs/analytics") / f"{today}.md"
    base.parent.mkdir(parents=True, exist_ok=True)
    base.write_text(report, encoding="utf-8")
    base.with_suffix(".json").write_text(
        json.dumps({"days": args.days, "generated": today, **data}, indent=2, default=str),
        encoding="utf-8")
    print(f"wrote {base} and {base.with_suffix('.json')}")

    ok = isinstance(data.get("ga4"), dict) or isinstance(data.get("gsc"), dict)
    if not ok:
        print("warning: neither GA4 nor GSC returned data — check setup.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
