---
name: analyze-prometheus-tsdb
description: Run a Prometheus TSDB snapshot that a CI job uploaded inside a local Prometheus container and query it — for before/after performance comparisons across legs and leak-vs-constant-offset questions a point-in-time pprof can't answer. Use when a CI run uploads a prometheus data backup and you need time-series (latency, goroutines, RSS, CPU) over the whole run, or to compare metrics before-vs-after across CI legs. Generic to any project whose CI backs up its Prometheus data dir.
---

# Analyze a Prometheus TSDB dump from CI

Check the project's `CLAUDE.md`/resources for the artifact name and metric names; the mechanics below are universal.

## Spin it up locally

```bash
run=<runId>
gh run download $run -n <prom-dump-artifact> -D /tmp/prom -R <owner>/<repo>

docker run -d --name prom -p 9091:9090 -v /tmp/prom/prometheus:/prometheus \
  prom/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus
sleep 5; curl -s localhost:9091/-/ready   # "Prometheus Server is Ready."
```

The dump contains WAL + chunks; Prometheus replays it on start.
Download multiple legs into separate containers (`-p 9092:9090`, …) to compare.
Clean up with `docker rm -f <name>`.

## Querying — the traps

- **URL-encode PromQL.**
  `curl "...?query={pod=~'x'}"` mangles `=~`.
  Always `curl -sG ... --data-urlencode "query=..."`.
- **Bound the `query_range` window.**
  `start=0&end=<far-future>` with a small step exceeds the ~11k-points-per-series limit and errors or returns nothing.
  Find the real window first, then query inside it with `step=30`: ```bash curl -sG localhost:9091/api/v1/query_range \ --data-urlencode "query=up{pod=~'<svc>.*'}" \ --data-urlencode "start=$(date -v-8H +%s)" --data-urlencode "end=$(date +%s)" \ --data-urlencode "step=60" # min/max timestamps in the result = the run window ```
- **Instant queries evaluate at "now"** with a 5-minute lookback — against a dump whose data ended hours ago they return empty or a stale last sample.
  Use `query_range` with explicit start/end, or pass `time=<ts>` inside the data window.
- **`increase(...[<window>s])` at the window's end** gives run totals (e.g. total CPU seconds).

## Per-pod, not `sum()` — the rollout-overlap artifact

`sum(...)` **double-counts during rollouts** — old and new pods coexist, so a leg that restarts a service several times appears to "use" 2× the memory/goroutines.
Query **per-pod** (no `sum()`), then take avg/max across all samples of all pod generations.
`count by ()` of the matched series tells you how many pod generations the leg churned through.

## Leak check from the time series

A constant offset and a leak look identical in a snapshot; the trend separates them:
- Split the run window into thirds; a healthy series has last-third avg ≤ first-third avg (load ramps down at suite end).
- The end-of-run baseline should land on the pprof goroutine snapshot from the same leg — that agreement cross-checks that both artifacts describe the same steady state.
- Rise-under-load → return-to-flat-baseline = per-request goroutines, fine.
  Monotonic climb, or a baseline that ratchets up after each phase = leak; switch to the pprof goroutine fingerprint (see `analyze-go-pprof`) to name the frame.

For cross-leg comparisons, normalize CPU by wall-clock (s/min) when legs differ in duration, and remember legs may run different test subsets — flag that next to any cross-leg number.

## Useful query shapes

```promql
# latency distribution over a suite
histogram_quantile(0.5, sum(rate(<histogram>_bucket[5m])) by (le))

# runtime, per pod (no sum() — see above)
go_goroutines{pod=~'<svc>.*'}
go_memstats_heap_inuse_bytes{pod=~'<svc>.*'} / 1048576
process_resident_memory_bytes{pod=~'<svc>.*'} / 1048576
increase(process_cpu_seconds_total{pod=~'<svc>.*'}[<run-window>s])
```
