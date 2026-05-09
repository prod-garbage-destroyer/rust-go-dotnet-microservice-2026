# Experiment Summary v2: Rust vs Go vs ASP.NET (JIT + AOT)

**Experiment slug:** `rust-go-dotnet-microservice-2026-v2`
**Generated from:** `artifacts/benchmark-results-v2.json`, `artifacts/charts-data-v2.json`
**Data status:** Partial matrix complete (`rust-axum`, `go-fiber`, `dotnet-jit`); `dotnet-aot` pending.

---

## Executive Read

- v2 prioritizes **tail latency** (p95/p99/p99.9), **overload behavior** (dropped iterations), and **saturation recovery** over max-latency anecdotes.
- Keep conclusions scenario-bound: wrk closed-loop throughput and k6 open-loop tail behavior are both required for final verdict.
- Report .NET results as separate targets: `dotnet-jit` and `dotnet-aot`.
- Interim signal from completed lanes: `go-fiber` leads on throughput and most tail/recovery metrics in this run window.
- Publish this cut as an **interim verdict**; keep `dotnet-aot` explicitly marked pending.

---

## Key Metrics Snapshot

| Target | Read RPS c=50 | Read RPS c=200 | Read p99 c=200 (wrk) | Tail p99 (k6) | Tail p99.9 (k6) | Tail dropped rate | Recovery p99 (k6) | Write RPS c=50 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| rust-axum | 5,384.54 | 5,970.25 | _n/a_ | 773.22 ms | 923.85 ms | 4,379.71 | 137.03 ms | 3,789.22 |
| go-fiber | 11,205.60 | 12,327.61 | _n/a_ | 511.99 ms | 1,004.28 ms | 1,889.13 | 94.81 ms | 4,510.48 |
| dotnet-jit | 9,251.80 | 9,520.04 | _n/a_ | 915.77 ms | 1,563.88 ms | 4,170.33 | 111.61 ms | 4,191.38 |
| dotnet-aot | _pending run_ | _pending run_ | _pending run_ | _pending run_ | _pending run_ | _pending run_ | _pending run_ | _pending run_ |

---

## Interpretation Framework (Use For Final Claims)

- **Throughput winner:** highest `read_rps_c200` with acceptable failure and dropped-iteration rates.
- **Tail winner:** lowest `tail_p99_ms` and `tail_p999_ms` under open-loop k6.
- **Overload stability winner:** lowest `tail_dropped_iterations_rate` and lower `tail_failed_rate`.
- **Recovery winner:** lowest `pool_p99_ms` post-saturation.
- **Write parity check:** compare `write_rps_c50` to confirm DB-bound workloads compress framework differences.

---

## Suggested Final Verdict Structure

1. **Most teams:** choose the target with best balance of c=200 throughput + tail p99/p99.9.
2. **Latency SLO teams:** prioritize p99/p99.9 and dropped iterations over headline RPS.
3. **.NET shops:** compare `dotnet-jit` vs `dotnet-aot` directly; do not mix them.
4. **Memory/cost-sensitive deploys:** combine this report with RSS/startup artifacts before final recommendation.

---

## Video-Safe Claims (Interim)

- Completed lanes in this publish cut: `rust-axum`, `go-fiber`, `dotnet-jit`.
- On completed lanes, `go-fiber` leads read throughput (`12,327.61 RPS @ c=200`) and k6 tail p99 (`511.99 ms`).
- `dotnet-jit` is mid-pack on throughput (`9,520.04 RPS @ c=200`) and has the highest tail p99/p99.9 in this cut.
- `rust-axum` is lowest on throughput in this window, with tail p99.9 (`923.85 ms`) below both `go-fiber` and `dotnet-jit`.
- `dotnet-aot` remains pending; do not present any JIT-vs-AOT winner yet.

---

## Data Provenance Checklist

- [x] `artifacts/benchmark-results-v2.json` generated from a real matrix run.
- [x] `artifacts/charts-data-v2.json` generated in same run window.
- [ ] `benchmark-results-v2.json` per target present in `bench/results/<target>/<run-id>/`.
- [x] No source paths reference `aggregate-smoke`.
