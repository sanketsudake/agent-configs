# Codecov query recipes (Python)

Verbose Python variants for the Codecov API steps in `SKILL.md`.
The curl fetches and `jq` filters live inline in the skill; these are the bulkier Python snippets.

## Print top-level totals (response shape)

```python
import json
d = json.load(open('/tmp/cov_main.json'))
t = d['totals']
print(f'coverage={t["coverage"]}%  lines={t["lines"]}  hits={t["hits"]}  misses={t["misses"]}  partials={t["partials"]}  files={t["files"]}')
print('files in payload:', len(d.get('files', [])))
```

Response shape of the `totals` endpoint:

```json
{
  "totals": {
    "coverage": 58.21,
    "lines": 20355,
    "hits": 11850,
    "misses": 6904,
    "partials": 1601,
    "files": 258
  },
  "files": [
    {
      "name": "pkg/foo/bar.go",
      "totals": { "coverage": 34.5, "lines": 93, "hits": 32, "misses": 58, "partials": 3 }
    }
  ]
}
```

The `totals` endpoint returns ALL files combined across ALL CI upload flags.
A local `go test` run (unit-only) will report a lower percentage.
The Codecov number is the source of truth for gap analysis.

## Rank packages by biggest gap (most uncovered lines)

```python
import json, collections

d = json.load(open('/tmp/cov_main.json'))
pkg = collections.defaultdict(lambda: [0, 0, 0, 0])  # lines, hits, misses, partials

for f in d['files']:
    name = f['name']
    t = f['totals']
    p = '/'.join(name.split('/')[:-1])  # strip filename -> package dir
    a = pkg[p]
    a[0] += t['lines']
    a[1] += t['hits']
    a[2] += t['misses']
    a[3] += t['partials']

rows = []
for p, (l, h, m, pa) in pkg.items():
    cov = 100 * h / l if l else 0
    uncovered = m + pa
    rows.append((uncovered, p, l, cov, m, pa))

rows.sort(reverse=True)
print(f'{"UNCOV":>6} {"COV%":>6} {"LINES":>6}  PACKAGE')
print('-' * 80)
for uncov, p, l, cov, m, pa in rows[:35]:
    print(f'{uncov:6d} {cov:6.1f} {l:6d}  {p}')
```

## Before/after comparison (two snapshots)

```python
import json, collections

def by_pkg(fn):
    d = json.load(open(fn))
    pkg = collections.defaultdict(lambda: [0, 0])
    for f in d['files']:
        p = '/'.join(f['name'].split('/')[:-1])
        t = f['totals']
        pkg[p][0] += t['lines']
        pkg[p][1] += t['hits']
    return {p: (100 * h / l if l else 0) for p, (l, h) in pkg.items()}

before = by_pkg('/tmp/cov_main_before.json')
after  = by_pkg('/tmp/cov_main_after.json')
rows = []
for p in after:
    b = before.get(p, 0); a = after[p]
    rows.append((a - b, p, b, a))
rows.sort(reverse=True)
print(f'{"DELTA":>6} {"BEFORE":>7} {"AFTER":>7}  PACKAGE')
for dlt, p, b, a in rows[:12]:
    if dlt > 0.5:
        print(f'{dlt:+6.1f} {b:7.1f} {a:7.1f}  {p}')
```
