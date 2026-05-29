# Methodology v3 — Rust vs Go vs ASP.NET Microservice Benchmark

## Experiment Overview

**Slug:** `rust-go-dotnet-microservice-2026-v3`
**Objective:** Produce the most defensible, reproducible cross-language backend microservice benchmark. Compare 5 lanes across 3 languages, measuring throughput, tail latency, memory, CPU efficiency, cold/warm startup, and saturation recovery.

## Targets (5 lanes)

| Lane | Language | Framework | Runtime | Port | Container Base |
|------|----------|-----------|---------|------|----------------|
| rust-axum | Rust | Axum 0.8 (hyper) | native AOT | 3001 | debian:bookworm-slim |
| go-fiber | Go | Fiber v2 (fasthttp) | native | 3002 | debian:bookworm-slim |
| go-nethttp-chi | Go | net/http (stdlib) + chi v5 | native | 3005 | debian:bookworm-slim |
| dotnet-jit | C# | ASP.NET Minimal API | JIT + R2R | 3003 | mcr.microsoft.com/dotnet/aspnet:10.0 |
| dotnet-aot | C# | ASP.NET Minimal API | Native AOT | 3004 | mcr.microsoft.com/dotnet/runtime-deps:10.0 |

## v2 → v3 Fairness Changes

All changes are documented in `fairness-policy-v3.md`. Key methodology changes:

1. **Per-endpoint warmup** — All measured endpoints receive 10s warmup at c=50 with actual request shapes before timed phase.
2. **Clean builds** — All build times measured from clean cache (`cargo clean`, `go clean -cache`, `dotnet clean`).
3. **Npgsql typed parameters** — All .NET queries use `NpgsqlParameter(NpgsqlDbType.*)`.
4. **Notify spawn hoisted** — Background task only spawned when `BENCH_NOTIFY_LOG=true`. During timed runs it's `false` → zero scheduling overhead.
5. **Rust hash hot path** — `finalize_into` with stack buffer, no per-round heap alloc.
6. **Single-pass json/roundtrip** — All targets use single-pass foreach/fold.
7. **Startup config verified** — Pool parity and notify disabled confirmed in startup logs before accepting a run.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | /health | Liveness probe |
| POST | /users | Create user (write + DB insert) |
| GET | /users/:id | Read single user |
| GET | /users | List users (read-heavy) |
| DELETE | /users/:id | Delete user |
| POST | /json/roundtrip | JSON decode/encode + aggregation |
| POST | /crypto/hash | CPU-bound SHA-256 (2000 rounds) |

## Benchmark Phases

### 1. Functional Verification
All endpoints hit with valid + invalid payloads. Failures exclude the target.

### 2. Warmup
- 20s at c=50 on `GET /health`
- 10s at c=50 on each workload endpoint with actual request shapes
- All warmup traffic discarded from results

### 3. Closed-Loop Throughput (wrk)
| Phase | Endpoint | Concurrency | Duration |
|-------|----------|-------------|----------|
| read-c50 | GET /users/:id | 50 | 30s |
| read-c200 | GET /users/:id | 200 | 30s |
| read-c500 | GET /users/:id | 500 | 30s |
| write-c50 | POST /users | 50 | 20s |

### 4. Open-Loop Tail Latency (k6)
Constant arrival rate, staged: 2000 → 5000 → 10000 → 15000 → 20000 RPS.
Duration: 90s total.
Metrics: p50/p95/p99/p99.9, error rate, dropped iterations.

### 5. Pool Saturation & Recovery (k6)
Closed-loop concurrency ladder: 50 → 100 → 200 → 400 → 800.
Sustain 60s at each level, then drop to c=50 for 60s recovery observation.
Metrics: RPS, p99, error rate, time to recover to p99 < 100ms.

### 6. CPU Efficiency (perf)
Single-endpoint wrk run at c=200 for 45s on `GET /users/:id`.
`perf stat` collects: cycles, instructions, branches, branch-misses, cache-misses.
Derived: cycles/request, instructions/request, IPC.

### 7. Cold/Warm Startup
- Process start → health-ready (startup_time_ms)
- First request latency
- Request #1000 latency
- Idle RSS (after startup, before warmup)
- Warmed RSS (after warmup phase)

## Environment

- **OS:** Linux (glibc, not musl)
- **Architecture:** x86_64
- **Container Runtime:** Podman
- **Database:** PostgreSQL 16, port 5433
- **Connection Pool:** min=5, max=20 (enforced and verified)
- **CPU Governor:** performance (no throttling)

## Run Configuration

```bash
export BENCH_USER_IDS="uuid1,uuid2,uuid3,..."
export BENCH_NOTIFY_LOG=false

# Single target
./bench/scripts/run-v3.sh rust-axum

# All targets sequentially
./bench/scripts/run-v3.sh all
```

## Build Commands

```bash
# Rust
cd implementations/rust-axum && cargo clean && cargo build --release

# Go Fiber
cd implementations/go-fiber && go clean -cache && go build -ldflags='-s -w' -o microservice .

# Go net/http + chi
cd implementations/go-nethttp-chi && go clean -cache && go build -ldflags='-s -w' -o microservice .

# .NET JIT (R2R)
cd implementations/dotnet-minimal/microservice && dotnet clean && dotnet publish -c Release -o publish

# .NET AOT
cd implementations/dotnet-aot/microservice && dotnet clean && dotnet publish -c Release -o publish
```

## Measurement Runs
- 7 measurement runs per target per phase
- Max 1 retry per failed run (infrastructure failures only)
- Performance outliers are not retried

## Required Artifacts
See `spec-v3.yaml` §artifacts for the complete list and schema.

## Known Limitations
1. **Single machine** — No distributed testing. All targets share host resources (sequential execution mitigates this).
2. **x86_64 only** — No ARM64 results. Apple Silicon users see different absolute numbers.
3. **PostgreSQL 16 only** — DB version may affect results. Pinned for reproducibility.
4. **glibc only** — Alpine/musl results are a separate scenario, not merged into baseline.
5. **Fiber is non-stdlib** — Documented in fairness policy. Use `go-nethttp-chi` for stdlib-tier comparisons.
