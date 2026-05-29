# Fairness Policy v3 — Rust vs Go (Fiber + net/http) vs ASP.NET (.NET 10 JIT + Native AOT)

## Scope
This policy governs the v3 benchmark for `rust-go-dotnet-microservice-2026-v3`.

Targets (5 lanes):
- rust-axum
- go-fiber
- go-nethttp-chi *(new)*
- dotnet-jit *(fixed)*
- dotnet-aot *(new)*

The purpose of v3 is to produce the most defensible, reproducible, apples-to-apples cross-language backend microservice benchmark possible, addressing every fairness concern raised against v2 in [issue #1](https://github.com/prod-garbage-destroyer/rust-go-dotnet-microservice-2026/issues/1).

## Changes from v2

### Blocking fixes (all applied)
1. **dotnet-aot lane added** — Native AOT compilation with `<PublishAot>true</PublishAot>`. Fully self-contained binary. No JIT, no tiered compilation.
2. **Per-endpoint warmup** — Every measured endpoint receives dedicated warmup traffic with actual request shapes before the timed phase. Eliminates tiered JIT asymmetry where only `/health` was warmed in v2.
3. **Fairness policy reconciled** — v2 had contradictory docs: `fairness-policy.md` said "No AOT" while `methodology-v2.md` listed `dotnet-aot` as a lane. v3 has a single source of truth.

### Should-fix items (all applied)
4. **Npgsql `AddWithValue` → typed `NpgsqlParameter`** — All .NET queries now use statically-typed `NpgsqlParameter(NpgsqlDbType.Varchar/Uuid)` instead of `AddWithValue()`, eliminating the per-call type inference tax.
5. **Rust crypto/hash stack-allocated** — `finalize_into(&mut [0u8; 32])` replaces `.to_vec()` per round. No heap alloc in the hot loop.
6. **Notify spawn hoisted** — All three implementations now check `BENCH_NOTIFY_LOG` *before* spawning the background task. When disabled (as required during timed runs), zero scheduling overhead.
7. **`.NET PublishReadyToRun` enabled** — JIT lane now precompiles framework assemblies. Symmetric with Rust's `lto = true + codegen-units = 1`.
8. **`.NET app log level Warning`** — Suppresses `Microsoft.AspNetCore: Warning` and all app-level Information during timed runs.
9. **`.NET crypto/hash `Convert.ToHexStringLower`** — Eliminates unnecessary `.ToLowerInvariant()` call.
10. **Single-pass json/roundtrip** — Rust and .NET now use single-pass foreach/fold instead of multi-pass .iter()/.Sum() chains. All three targets use identical iteration strategy.

### Known Asymmetries (documented, not "fixed")
These asymmetries remain by design because they reflect genuine runtime characteristics or framework choices. They are documented here so readers can self-weight results.

#### 1. Go Fiber uses fasthttp (non-stdlib)
- **Status:** Kept as a separate lane. `go-nethttp-chi` lane added for stdlib-tier comparison.
- **Impact:** Fiber is typically 30–40% faster than `net/http` on microbenchmarks. Both lanes are reported independently.
- **Recommendation:** Use `go-nethttp-chi` for apples-to-apples comparisons with Axum/Kestrel. Use `go-fiber` to understand Go's maximum possible throughput.

#### 2. .NET AOT compile time is 30–60x slower than JIT
- **Status:** Documented. AOT build time is reported separately from JIT build time.
- **Impact:** AOT is a deployment-mode choice, not a development-mode choice. Build-time comparisons use JIT numbers.

#### 3. .NET AOT runtime container uses `runtime-deps:10.0` (smaller base)
- **Status:** Documented. AOT binary doesn't need the .NET runtime installed.
- **Impact:** Container image size for AOT is smaller than JIT. This is a legitimate AOT advantage, not an asymmetry.

#### 4. Go goroutines vs Tokio tasks vs Task.Run have different scheduling costs
- **Status:** Documented in methodology. The notify spawn hoist eliminates this from timed runs.
- **Impact:** When `BENCH_NOTIFY_LOG=true` (development mode), scheduling costs differ. This is not measured.

## Same Functionality
All targets implement identical endpoint behavior:
- All 7 endpoints from spec-v3.yaml
- Identical validation rules (name 1-100 chars, valid email)
- Identical status codes (201, 200, 404, 204, 422)
- Identical response field names and types

## Same Data Layer
- PostgreSQL 16, shared host instance
- Single schema: `users` table with UUID PK, VARCHAR name/email, TIMESTAMPTZ created_at
- Same indexes: UNIQUE on email
- Same seed strategy

Connection pool: min=5, max=20, enforced and verified at startup for every target.

## Same Runtime Envelope
- Same host machine per run set
- Same CPU governor, no thermal throttling
- One target active at a time during measurements
- No sidecars or external caches

## Middleware and Logging Parity
- Request logging: disabled
- Access logs: disabled
- Tracing/APM: disabled
- App log level: Warning (all targets)
- Startup config log: enabled (used for parity verification)

## Warmup and Lifecycle
Before each measured phase:
- 20s warmup at c=50 on `GET /health`
- 10s discarded endpoint-specific warmup for EVERY timed workload using actual request shapes
  - `GET /users/:id`
  - `POST /users`
  - `POST /json/roundtrip`
  - `POST /crypto/hash`
- Restart target between cold-start measurements
- `BENCH_NOTIFY_LOG=false` enforced and verified in startup config log

## Benchmark Methods
Two load models:
- Closed-loop (wrk): throughput and saturation behavior
- Open-loop (k6 constant-arrival-rate): tail latency and overload behavior

## Tail Latency Reporting
Each measured phase reports: p50, p95, p99, p99.9, error rate, dropped iterations.

## Cold vs Warm Start
Per target: startup_time_ms, first request latency, request #1000 latency, idle RSS, warmed RSS.

.NET JIT and AOT are separate targets — numbers are never merged.

## CPU Efficiency
`perf stat` counters: cycles, instructions, branches, branch-misses, cache-misses.
Derived: cycles/request, instructions/request, IPC.

## Saturation and Recovery
Concurrency ladder: 50 → 100 → 200 → 400 → 800, then drop to 50.
Outputs: peak error rate, p99 recovery trajectory, time-to-recover threshold.

## Clean Build Requirement
All build measurements use clean caches:
- Rust: `cargo clean`
- Go: `go clean -cache`
- .NET: `dotnet clean`

Build times measured with `/usr/bin/time -v`. Incremental builds are not used for timing.

## Retry and Exclusion Rules
- Max 1 retry per failed run
- Retries only for infrastructure failures
- Performance outliers are not retried
- Runs with incorrect startup config are discarded

## Required Artifacts
- `artifacts/benchmark-results-v3.json`
- `artifacts/tail-latency-v3.json`
- `artifacts/cpu-efficiency-v3.json`
- `artifacts/pool-saturation-recovery-v3.json`
- `artifacts/startup-cold-warm-v3.json`
- `artifacts/charts-data-v3.json`
- `artifacts/summary-v3.md`
- `artifacts/methodology-v3.md`
- `artifacts/fairness-report-v3.md`

## Claim Policy
Public claims must cite: metric + scenario + target + artifact source.

Examples:
- Allowed: "dotnet-aot has 43% lower p99.9 under open-loop 20k RPS compared to dotnet-jit in this environment."
- Allowed: "go-nethttp-chi throughput at c=200 is X% of go-fiber throughput."
- Allowed: "rust-axum leads idle memory at 8.2 MB across all 5 targets."
- Not allowed: "X is always fastest" without scenario qualifier.
- Not allowed: Merging JIT and AOT numbers for .NET.
- Not allowed: Comparing go-fiber throughput against dotnet-jit without mentioning the framework-class asymmetry.

## Reviewer Acknowledgment
This policy incorporates the fairness review by [nikitaclicks](https://github.com/nikitaclicks) in [issue #1](https://github.com/prod-garbage-destroyer/rust-go-dotnet-microservice-2026/issues/1). All blocking, should-fix, and should-document items from that review are addressed in v3.
