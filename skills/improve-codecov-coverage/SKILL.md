---
name: improve-codecov-coverage
description: Use when raising test coverage on a Go project that reports to Codecov (triggers "improve code coverage", "cover package X", "find coverage gaps"). Fetches Codecov totals, ranks low-covered packages, writes targeted tests, and verifies the delta. Generic to any Go + Codecov project.
---

# Improve Codecov Coverage (Go)

Work in an isolated git worktree — use the `using-git-worktrees` skill.

---

## 1. Fetch the Codecov Baseline

No auth token is required for public repos.

```bash
# Fetch combined coverage for main branch
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=main" \
  -o /tmp/cov_main.json

# For a PR branch (after CI runs)
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=<branch-name>" \
  -o /tmp/cov_pr.json
```

The `totals` endpoint returns ALL files combined across ALL CI upload flags, so it is the source of truth for gap analysis (a local unit-only `go test` reports lower).
For the Python snippet to print top-level totals and the JSON response shape, see `reference/codecov-recipes.md`.

---

## 2. Rank Low-Coverage Targets

### By file within a package

```bash
jq -r '
  .files[] | select(.name | startswith("pkg/mypackage"))
  | select(.totals.coverage < 80)
  | "\(.totals.misses + .totals.partials)\t\(.totals.coverage)%\t\(.name)"
' /tmp/cov_main.json | sort -rn | head -30
```

For ranking by package (biggest gap first) and the before/after-snapshot comparison, run the Python recipes in `reference/codecov-recipes.md`.

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

Most setups use two upload flags — `unittests` (from `go test -coverprofile`) and `integration` — and Codecov merges them into the combined number shown in the UI.
A local unit-only run is therefore lower than the Codecov number.
Integration coverage may come from a server binary built with `-cover` + `GOCOVERDIR`, collected from running pods and merged:

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

1. Can the function be exercised with fake/in-memory clients only? → Write a unit test.
   Runs locally in seconds.
2. Does the function require a real running server, runtime, or external process lifecycle? → Write an integration test (CI-only for full verification).
3. Check your project's CI workflow to see if integration tests run the CLI/library in-process — if yes, adding an integration test covers both the command handler and server-side code simultaneously.

- Write table-driven unit tests using the project's existing fakes/clientset.
- For integration tests, follow the project's test-framework docs.

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

A copy-paste cheat-sheet of the fetch/profile/validate commands lives in `reference/quick-reference.md`.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using local unit coverage as the gap analysis baseline | Always fetch Codecov first. Local unit-only can be dramatically lower than Codecov combined. |
| Checking Codecov immediately after CI finishes | The `integration` flag can lag 5–15 min. Poll the API as shown above. |
| Writing unit tests for generated files (e.g. `zz_generated_*.go`) | Check the project's `codecov.yml` `ignore:` block. Generated files are excluded from the denominator. |
