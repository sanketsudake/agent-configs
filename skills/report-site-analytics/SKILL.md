---
name: report-site-analytics
description: Use to pull a GA4 + Google Search Console report (top pages, queries, CTR, near-miss positions) into a dated markdown/JSON summary for an SEO/reachability pass. Triggers "analytics report", "what's my search traffic", "GSC report". Generic to any site with GA4 + Search Console configured.
---

# Report site analytics (GA4 + Search Console)

Run at the start of a reachability/SEO cycle, to surface low-CTR-high-impression pages and near-miss queries.

## Workflow

Requires Application Default Credentials with access to the GA4 property and GSC site, plus `GA4_PROPERTY_ID` / `GSC_SITE_URL` (or the flags):

```bash
python3 <skill-dir>/analytics-report.py \
  --property <ga4-numeric-id> \
  --site https://my.site/ \
  --days 28 \
  --out docs/analytics/<date>.md
```

## Guardrails

- Search Console lags ~3 days; run cycles ~monthly so trends are real.
- Reports may contain traffic data — keep them gitignored.

## Output

A markdown report (+ JSON) of top pages, queries, CTR, and positions.
