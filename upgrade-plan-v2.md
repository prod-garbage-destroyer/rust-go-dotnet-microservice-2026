# Upgrade Plan — Benchmark v2

This plan upgrades `rust-go-dotnet-microservice-2026` from basic throughput/avg-latency reporting to authoritative, reproducible benchmarking focused on tail latency, startup behavior, CPU efficiency, and recovery after saturation.

## Why v2
- Current artifacts discuss p99 but mostly report avg/max latency.
- Benchmark scripts are not versioned in-repo.
- Fairness policy claims pool parity, but .NET pool caps are not explicitly enforced in code.
- .NET Native AOT is currently out of scope and needs a controlled lane.

## Deliverables
- `spec-v2.yaml`
- `fairness-policy-v2.md`
- New benchmark harness files in `bench/`
- Additional endpoints for JSON-heavy and CPU-heavy scenarios
- New v2 artifacts (tail latency, CPU counters, cold/warm startup, saturation recovery)

## Work Breakdown

### 1) Reproducible Benchmark Harness
Create benchmark assets in-repo:
- `bench/wrk/get-users.lua`
- `bench/wrk/post-users.lua`
- `bench/k6/tail-latency.js`
- `bench/k6/scenarios/pool-saturation-recovery.js`
- `bench/scripts/run-v2.sh`
- `bench/scripts/collect-metrics.sh`

Acceptance:
- No benchmark script referenced from `/tmp`
- Single command produces raw logs and normalized JSON outputs

### 2) Fairness Fixes in Implementations
Apply parity settings across targets:
- Explicit DB pool limits min=5 max=20 in all targets
- Disable request/access logging in timed runs
- Confirm equivalent middleware toggles

Acceptance:
- Runtime config dump per target confirms parity
- `artifacts/methodology-v2.md` includes proof table

### 3) Add v2 Workload Endpoints
Add two endpoints to each implementation:
- `POST /json/roundtrip` (JSON decode + encode path)
- `POST /crypto/hash` (CPU-bound hash operation)

Use equivalent payload shapes and cost parameters.

Acceptance:
- Shared functional test vectors pass for all targets
- Endpoint behavior documented in v2 methodology

### 4) Cold/Warm + JIT/AOT Lane
Introduce .NET split targets:
- `dotnet-jit`
- `dotnet-aot`

Measure:
- startup to health-ready
- first request latency
- request #1000 latency
- idle and warmed RSS

Acceptance:
- `artifacts/startup-cold-warm.json` includes all four targets

### 5) Tail Latency First-Class Reporting
Run open-loop tests with staged arrival rates and capture:
- p50/p95/p99/p99.9
- error rate
- dropped iterations

Acceptance:
- `artifacts/tail-latency.json` and chart data generated
- Summary claims use percentile metrics, not max-only anecdotes

### 6) CPU Efficiency Collection
Collect Linux perf counters for matched workload windows:
- cycles, instructions, branch misses, cache misses

Derive:
- cycles/request
- instructions/request
- IPC

Acceptance:
- `artifacts/cpu-efficiency.json` reproducibly generated

### 7) Saturation and Recovery Test
Run concurrency ladder until pool bottleneck then step down load.

Capture:
- saturation error rate
- p99 recovery trajectory
- time-to-recover threshold

Acceptance:
- `artifacts/pool-saturation-recovery.json` with time series

### 8) Final Reporting and Video-Ready Data
Produce:
- `artifacts/benchmark-results-v2.json`
- `artifacts/charts-data-v2.json`
- `artifacts/methodology-v2.md`
- `artifacts/summary-v2.md`

Include a compact comparison table for overlay:
- idle RSS
- warmed RSS
- p99/p99.9
- throughput
- first request latency
- cycles/request
- recovery time

## Execution Order
1. Harness + parity fixes
2. Endpoint additions + tests
3. JIT/AOT build lane
4. Tail + saturation + CPU runs
5. Artifact generation + summary

## Risk Controls
- Pin tool versions (wrk, k6, perf)
- Reject runs with thermal throttling or background CPU spikes
- Separate baseline (glibc) from optional musl scenario
- Keep claim language scenario-bound (no universal speed claims)

## Definition of Done
- All required v2 artifacts present and internally consistent
- Fairness policy checks pass with no unresolved violations
- Summary conclusions trace directly to reproducible artifact data
