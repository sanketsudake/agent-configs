---
name: improve-codecov-coverage
description: Use when raising test coverage on a Go project that reports to Codecov (triggers "improve code coverage", "cover package X", "find coverage gaps"). Fetches Codecov totals, ranks low-covered packages, writes targeted tests, and verifies the delta. Generic to any Go + Codecov project.
---

# Improve Codecov Coverage (Go)

## Overview

Codecov combines coverage from multiple CI upload streams (e.g. `unittests` + `integration`).
Local unit-only runs will be lower than Codecov's combined number — always fetch the Codecov baseline first to see the real gaps before deciding where to invest.
Work in an isolated git worktree — use the `using-git-worktrees` skill.

---

## 1. Fetch the Codecov Baseline

No auth token is required for public repos.

```bash
# Fetch combined coverage for main branch
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=main" \
  -o /tmp/cov_main.json

# Print top-level totals
python3 -c "
import json
d = json.load(open('/tmp/cov_main.json'))
t = d['totals']
print(f'coverage={t[\"coverage\"]}%  lines={t[\"lines\"]}  hits={t[\"hits\"]}  misses={t[\"misses\"]}  partials={t[\"partials\"]}  files={t[\"files\"]}')
print('files in payload:', len(d.get('files', [])))
"
```

Response shape:

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

For a PR branch (after CI runs):

```bash
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=<branch-name>" \
  -o /tmp/cov_pr.json
```

---

## 2. Rank Low-Coverage Targets

### By package (biggest gap first — most uncovered lines)

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

### By file within a package

```bash
jq -r '
  .files[] | select(.name | startswith("pkg/mypackage"))
  | select(.totals.coverage < 80)
  | "\(.totals.misses + .totals.partials)\t\(.totals.coverage)%\t\(.name)"
' /tmp/cov_main.json | sort -rn | head -30
```

### Before/after comparison (two snapshots)

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

---

## 3. Measure Coverage Locally (Unit Tests)

```bash
# Single package
go test -race -coverprofile=/tmp/cov_pkg.out ./pkg/mypackage/...
go tool cover -func=/tmp/cov_pkg.out | tail -1          # total
go tool cover -func=/tmp/cov_pkg.out | grep " 0.0%"    # uncovered functions
go tool cover -html=/tmp/cov_pkg.out -o /tmp/cov.html   # visual report

# Find functions below 20%
go tool cover -func=/tmp/cov_pkg.out | awk -F'\t+' '{gsub(/%/,"",$3); if($3+0 < 20) print}' \
  | sort -t$'\t' -k3 -n | head -30

# Full suite (matches CI 'unittests' flag)
go test -race -coverprofile=coverage.txt -covermode=atomic --coverpkg=./... ./...
go tool cover -func=coverage.txt | tail -1
```

---

## 4. Understand the CI Coverage Upload Model

Most Go + Codecov setups use two (or more) upload flags. Codecov merges them into the combined number shown in the UI.

**Typical two-flag setup:**

- **`unittests` flag** — produced by the unit-test CI job (`go test -race -coverprofile=coverage.txt ...`), uploaded via `codecov/codecov-action`.
- **`integration` flag** — produced by an integration test job. Two common mechanisms:
  - **Test binary built with `-cover`** — runs integration tests in-process; coverage counters update live.
  - **Server binary built with `-cover` + `GOCOVERDIR`** — coverage data collected from running pods/containers and merged with `go tool covdata textfmt`.

**Merge integration covdata and convert to text format:**

```bash
go tool covdata textfmt -i="covdata-raw,covdata-cli" -o=integration-coverage.txt
go tool cover -func=integration-coverage.txt | tail -1
```

**Implication for targeting:**
- File at 0% on Codecov → untouched by ALL flags → guaranteed unit-test win.
- File at N% on Codecov but 0% locally → covered only by the integration flag → unit tests still move the combined number.
- File at N% both ways → already unit-covered.

---

## 5. Write Tests to Close Gaps

### Decision: unit vs integration test

1. Can the function be exercised with fake/in-memory clients only? → Write a unit test (table-driven; use your client library's fake clientset). Runs locally in seconds.
2. Does the function require a real running server, runtime, or external process lifecycle? → Write an integration test (CI-only for full verification).
3. Check your project's CI workflow to see if integration tests run the CLI/library in-process — if yes, adding an integration test covers both the command handler and server-side code simultaneously.

### Unit test pattern (table-driven, fake clients)

```go
func TestMyFunction(t *testing.T) {
    tests := []struct {
        name    string
        input   MyInput
        want    MyOutput
        wantErr bool
    }{
        {"happy path", validInput, expectedOutput, false},
        {"error path", badInput, MyOutput{}, true},
    }
    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            // Use the fake clientset your client library provides
            fakeClient := myfake.NewSimpleClientset(preExistingObjects...)
            got, err := MyFunction(context.Background(), fakeClient, tc.input)
            if tc.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tc.want, got)
        })
    }
}
```

### Integration test pattern (in-process CLI, build tag)

```go
//go:build integration

func TestMyCLICommand(t *testing.T) {
    t.Parallel()
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
    defer cancel()

    f := framework.Connect(t)
    ns := f.NewTestNamespace(t)

    // Call the CLI in-process; coverage counters update in real-time
    ns.CLI(t, ctx, "myresource", "create", "--name", "test-obj", "--flag", "value")
    ns.CLI(t, ctx, "myresource", "get",    "--name", "test-obj")
    ns.CLI(t, ctx, "myresource", "delete", "--name", "test-obj")
}
```

---

## 6. Iterate and Verify

### Per-package loop

```bash
go test -race -coverprofile=/tmp/cov_pkg.out ./pkg/mypackage/
go tool cover -func=/tmp/cov_pkg.out | tail -1          # package total
go tool cover -func=/tmp/cov_pkg.out | grep " 0.0%"    # still-uncovered functions
golangci-lint run ./pkg/mypackage/...
go vet ./pkg/mypackage/
```

### Post-PR verification (poll Codecov after CI)

The `integration` flag can lag 5–15 minutes after CI finishes before appearing in Codecov.

```bash
for i in $(seq 1 12); do
  tot=$(curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=<branch>")
  val=$(echo "$tot" | jq -r '.files[] | select(.name == "pkg/mypackage/myfile.go") | .totals.coverage')
  echo "iter $i: coverage=$val%"
  if [ -n "$val" ] && [ "${val%%.*}" != "0" ]; then
    echo "SETTLED"
    break
  fi
  sleep 75
done
```

---

## Quick Reference

```bash
# Fetch combined coverage for main
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=main" -o /tmp/cov.json

# Fetch for a PR branch
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=<branch>" -o /tmp/cov_pr.json

# Local unit test + profile
go test -race -coverprofile=/tmp/cov.out ./pkg/mypackage/...
go tool cover -func=/tmp/cov.out | tail -1
go tool cover -func=/tmp/cov.out | grep " 0.0%"
go tool cover -html=/tmp/cov.out -o /tmp/cov.html

# Full suite (matches CI unittests flag)
go test -race -coverprofile=coverage.txt -covermode=atomic --coverpkg=./... ./...
go tool cover -func=coverage.txt | tail -1

# Merge integration covdata and convert
go tool covdata textfmt -i="covdata-raw,covdata-cli" -o=integration-coverage.txt
go tool cover -func=integration-coverage.txt | tail -1

# Validate before commit
golangci-lint run ./pkg/mypackage/...
go vet ./pkg/mypackage/...
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using local unit coverage as the gap analysis baseline | Always fetch Codecov first. Local unit-only can be dramatically lower than Codecov combined. |
| Checking Codecov immediately after CI finishes | The `integration` flag can lag 5–15 min. Poll the API as shown above. |
| Writing unit tests for generated files (e.g. `zz_generated_*.go`) | Check the project's `codecov.yml` `ignore:` block. Generated files are excluded from the denominator. |
| Writing unit tests for functions that require a real runtime (pods, sockets, external processes) | These are already covered by the integration flag. Confirm by comparing Codecov per-file vs local. Use integration tests instead. |
| Trusting `file_report` endpoint line-level data | The `line_coverage` second value can show `1` for untouched lines. Rely on per-file `totals.coverage`, `totals.misses`, `totals.hits` from the `totals` endpoint. |
| `git add -A` in the worktree | Stage specific files explicitly. |
| Private repo Codecov fetch without a token | Private repos require `Authorization: Bearer <token>`. Public repos need no token. |
