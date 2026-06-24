---
name: analyze-go-pprof
description: Pull the heap/goroutine pprof profiles a CI job captured, separate a real leak from baseline cost, and quantify a fix's before/after delta. Use for "where is the memory/compute going", "is this a leak", "verify the perf fix", "compare profiles from the latest CI run", or when a Go service's CI run uploads pprof artifacts. Generic to any Go project whose CI captures /debug/pprof dumps.
---

# Analyze Go pprof profiles from CI

Assumes the CI job captures `/debug/pprof/heap` and `/debug/pprof/goroutine?debug=1` into an artifact (often gated behind a `pprof.enabled`-style flag/profile, so the dumps exist on the runs that enable it, not arbitrary branches).
Check the project's `CLAUDE.md`/resources for the exact artifact name and which services it covers.

## Download

```bash
run=$(gh run list --branch <branch> --workflow="<ci>" --limit 1 --json databaseId -q '.[0].databaseId')
gh api repos/<owner>/<repo>/actions/runs/$run/artifacts --jq '.artifacts[].name' | grep -i pprof
rm -rf /tmp/pp && mkdir /tmp/pp
gh run download $run -n <pprof-artifact-name> -D /tmp/pp
```

`go tool pprof` ships with the Go toolchain.
`.pprof` files are standard; the goroutine `.txt` is `debug=1` text.

## Heap analysis

```bash
# Top live-heap consumers (flat = allocated by that frame itself)
go tool pprof -top -inuse_space -nodecount=15 /tmp/pp/<svc>-heap.pprof

# Cumulative — who PULLS the allocations (init chains, logger factories, etc.)
go tool pprof -top -inuse_space -cum -nodecount=18 /tmp/pp/<svc>-heap.pprof

# Is a specific allocator still present? (confirm a fix removed it)
go tool pprof -top -inuse_space /tmp/pp/<svc>-heap.pprof | grep -iE '<allocator-frame>'
```

- `-inuse_space` = live heap at capture (steady-state footprint).
  `-alloc_space` shows cumulative churn but heap captures are inuse.
- Always run `-cum` too: the flat top is often a leaf (`zapcore.newCounters`, `<pkg>.init`); the cumulative view names the caller that explains *why* it's allocated.

## Goroutine analysis

```bash
head -1 /tmp/pp/<svc>-goroutine.txt   # "goroutine profile: total N"

# Group goroutines by top stack frame, count each
awk '/^[0-9]+ @/ { cnt=$1; getline; sub(/^#[ \t]+0x[0-9a-f]+[ \t]+/,"",$0); gsub(/^[ \t]+/,""); print cnt"\t"$1 }' \
  /tmp/pp/<svc>-goroutine.txt | sort -rn | head -12

# Count a specific suspect signature (leak fingerprint)
grep -c "<suspect-frame>" /tmp/pp/<svc>-goroutine.txt
```

A leaked goroutine shows up as a high count for one app frame that should be 1-per-something (e.g. a per-pool worker at 44 when it leaked, 1 after the fix).

## Leak vs baseline — classify before proposing work

| Pattern | Classification | Action |
|---|---|---|
| Prometheus summary `newStream`/`quantile.newStream`, scales with label cardinality | Reducible — convert `SummaryVec`→`HistogramVec` | Fix |
| `sync.Map`/cache entry count grows with churn, never deleted | Leak | Fix (delete on cleanup path) |
| App goroutine count grows per pool/function/request, no `ctx.Done()` exit | Leak | Fix (bound or cancel) |
| `*.init` / package-var allocation via package-level `GetLogger()` vars | One-time baseline, never freed but constant | Usually leave; only fixable structurally |
| k8s scheme registration, protobuf/cbor/regexp init | Baseline | Leave |

Facts that drive the classification:
- **Constant init cost = baseline; monotonic growth = leak.**
  A package-scope `var log = GetLogger()` or scheme/protobuf init is allocated once and never freed but stays constant — leave it.
  A count that climbs per request/pool/object with no bounded exit is a leak.
- **A `SummaryVec` keeps a per-series quantile stream**; cost scales with active label combinations.
  A histogram uses fixed buckets — cheaper and aggregatable across replicas.
- **A tiny CI cluster hides scale-dependent costs.**
  Absence in the profile ≠ absence at scale — reason about cardinality/pod-count separately.

## Quantify a fix: before/after

Download an artifact from a run *before* the fix and one *after*, then compare **composition, not raw totals** (totals drift run-to-run with cluster activity):

```bash
grep -c '<leaked-frame>' /tmp/before/<svc>-goroutine.txt   # e.g. 44
grep -c '<leaked-frame>' /tmp/after/<svc>-goroutine.txt     # e.g. 1
go tool pprof -top -inuse_space /tmp/before/<svc>-heap.pprof | grep -i '<allocator>'
go tool pprof -top -inuse_space /tmp/after/<svc>-heap.pprof  | grep -i '<allocator>' || echo "gone"
```

"this frame went 44→1" or "summary streams no longer present" is the durable signal.

## Gotchas

- **No pprof artifact on the run?**
  The branch didn't build with the profiling flag enabled, or path filters skipped the job entirely.
- **Capture is best-effort.**
  Steps often curl with `|| echo "capture failed"` and upload with `if-no-files-found: ignore`, so a leg can ship a partial set or nothing (service mid-restart, deployment torn down early).
  Recovery: pull the same files from an earlier round of the same PR whose code is identical (confirm the commit delta is docs/workflow-only), or from another leg.
- Cross-check against a Prometheus TSDB dump (see the `analyze-prometheus-tsdb` skill) to distinguish a constant offset from growth over time.
- **Histogram bucket choice matters**: a lifetime metric (seconds→hours) needs `ExponentialBuckets`, not `DefBuckets` (which top out at 10s and dump everything into `+Inf`).
