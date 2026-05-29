# Fairness Policy v2 — Rust vs Go vs ASP.NET (.NET 10 JIT + Native AOT)

## Scope
This policy governs the v2 benchmark for `rust-go-dotnet-microservice-2026-v2`.

Targets:
- rust-axum
- go-fiber
- dotnet-jit
- dotnet-aot

The objective is to compare runtime behavior, tail latency, memory profile, startup behavior, and recovery characteristics under equal constraints.

## Same Functionality
All targets must implement the same endpoint behavior and response contracts:
- Existing endpoints from `spec.yaml`
- New JSON-heavy endpoint: `POST /json/roundtrip`
- New CPU-heavy endpoint: `POST /crypto/hash`

Validation rules, status codes, and response fields must be equivalent across targets.

## Same Data Layer
- PostgreSQL 16, shared host instance
- Single schema and migration SQL
- Same indexes and constraints
- Same seed strategy for read-heavy workloads

Connection pooling must be explicitly configured and verified at runtime for every target:
- min=5
- max=20

Any target that does not enforce the same pool cap is considered non-compliant and excluded from winner claims until corrected.

## Same Runtime Envelope
- Same host machine per run set
- Same CPU governor and no thermal-throttling events during accepted runs
- One target active at a time during measurements
- No extra sidecars or external caches for any target

## Container Base Image and libc Disclosure
To avoid Alpine/musl ambiguity, each target must publish:
- Base image
- libc type (glibc or musl)
- Kernel version

v2 default is glibc for all production benchmark runs.

If a musl run is included, it must be labeled as an additional scenario, not merged into baseline rankings.

## Middleware and Logging Parity
- Request logging: disabled for all targets during timed runs
- Access logs: disabled
- Tracing exporters/APM: disabled
- Startup logs allowed

Any middleware enabled in one target must be enabled equivalently in all targets or disabled everywhere.

## Warmup and Lifecycle
Before each measured phase:
- 20s warmup at c=50 on `GET /health`
- Discarded endpoint-specific warmup for every timed workload using the same request shape as the measured run
- Restart target between cold-start measurements
- Warmup traffic discarded from results

## Benchmark Methods
Use two load models:
- Closed-loop (wrk): throughput and saturation behavior
- Open-loop (k6 constant-arrival-rate): tail latency and overload behavior

This split prevents over-reliance on a single tool and reduces coordinated-omission blind spots.

## Tail Latency Reporting Requirements
Each measured phase must report:
- p50
- p95
- p99
- p99.9
- error rate
- dropped iterations (for open-loop)

Do not use max latency as the primary evidence for claims.

## Cold vs Warm Start Reporting
For each target:
- Process start to health-ready (startup_time_ms)
- First request latency
- Request #1000 latency
- Idle RSS
- Warmed RSS

For .NET specifically, JIT and AOT are separate targets and cannot be merged.

## CPU Efficiency Reporting
Collect `perf stat` counters for equivalent workloads:
- cycles
- instructions
- branches
- branch-misses
- cache-misses

Report derived metrics:
- cycles/request
- instructions/request
- IPC

## Saturation and Recovery Reporting
Stress targets past pool saturation using matched concurrency ladders, then drop load.

Required outputs:
- Peak error rate at saturation
- Time to recover to stable p99 threshold after load drop
- Recovery curve data points over time

## Retry and Exclusion Rules
- Max 1 retry per failed run
- Retries allowed only for infrastructure failures (port, process crash, DB unavailable)
- Performance outliers are not retried away

If functional tests fail, target is excluded from benchmark charts and marked failed.

## Required Artifacts
The benchmark is incomplete unless all required v2 artifacts exist:
- `artifacts/benchmark-results-v2.json`
- `artifacts/tail-latency.json`
- `artifacts/cpu-efficiency.json`
- `artifacts/pool-saturation-recovery.json`
- `artifacts/startup-cold-warm.json`
- `artifacts/charts-data-v2.json`
- `artifacts/summary-v2.md`
- `artifacts/methodology-v2.md`

## Claim Policy
Public claims must cite metric + scenario + artifact source.

Examples:
- Allowed: "Go leads throughput at c=200 in IO-read-heavy closed-loop runs."
- Allowed: "Rust has lower p99.9 under open-loop overload in this environment."
- Not allowed: "X is always faster" without scenario qualifier.
