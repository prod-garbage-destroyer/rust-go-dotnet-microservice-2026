# Methodology v2: Reproducible Benchmark Protocol

This document defines how v2 results are produced and what checks must pass before any public claim.

---

## 1) Targets and Lanes

- `rust-axum`
- `go-fiber`
- `dotnet-jit`
- `dotnet-aot`

Rules:
- Treat `dotnet-jit` and `dotnet-aot` as separate targets.
- Never average or merge JIT and AOT into one .NET number.

---

## 2) Workloads

### wrk closed-loop baseline
- Warmup: `GET /health`, c=50, 10s
- Read: `GET /users/:id`, c=50/200/500, 30s
- Write: `POST /users`, c=50, 20s

### k6 open-loop tail
- Script: `bench/k6/tail-latency.js`
- Staged arrival-rate ramps
- Required metrics: p95, p99, p99.9, failed rate, dropped iterations

### k6 saturation + recovery
- Script: `bench/k6/scenarios/pool-saturation-recovery.js`
- Ramping-vus saturation ladder + recovery window
- Required metrics: p99, failed rate, dropped iterations

### New endpoint workloads
- `POST /json/roundtrip` (JSON-heavy)
- `POST /crypto/hash` (CPU-heavy)

---

## 3) Fairness Constraints

- Database: same PostgreSQL instance and schema
- Pool parity: min=5, max=20 in all targets
- Logging parity: `BENCH_NOTIFY_LOG=false` during timed runs
- One benchmarked target process active per measured run
- Same seeded ID list for `/users/:id` workloads

---

## 4) Tooling and Scripts

- Per-target baseline + k6 run: `bench/scripts/run-v2-all.sh`
- Dotnet lane run: `bench/scripts/run-dotnet-lane-v2-all.sh`
- Full matrix run: `bench/scripts/run-v2-matrix.sh`
- Per-target normalized merge output: `benchmark-results-v2.json` in each run dir
- Cross-target aggregate: `bench/scripts/aggregate-v2-results.sh`

---

## 5) Artifact Requirements

The run is considered valid only if all are present:

- `artifacts/benchmark-results-v2.json`
- `artifacts/charts-data-v2.json`
- `artifacts/summary-v2.md`
- `artifacts/methodology-v2.md`

And each target run directory includes:

- `benchmark-results.json` (wrk normalized)
- `k6-tail-normalized.json`
- `k6-pool-saturation-normalized.json`
- `benchmark-results-v2.json` (merged per target)

---

## 6) Quality Gates Before Publishing

1. **Schema gate**
   - `schema_version` fields exist and match expected values.

2. **Completeness gate**
   - `summary_rows` includes all intended targets.
   - No required metric keys are null for final report rows.

3. **Provenance gate**
   - Source file paths in aggregate point to real run directories.
   - No smoke/test fixture paths.

4. **Fairness gate**
   - Startup config logs confirm pool parity and notify logging disabled.

5. **Claim gate**
   - Every public claim cites metric + scenario + target.

---

## 7) Claim Language Policy

Allowed:
- "X leads tail p99 under open-loop k6 in this benchmark environment."
- "Y has lower dropped-iteration rate under overload in this run."

Disallowed:
- "X is always faster" (unqualified universal claim)
- Any claim combining .NET JIT and AOT without explicit labeling

---

## 8) Known Environment Caveats

- Absolute numbers vary by hardware and OS; compare targets within the same run window.
- For AOT lane, runtime identifier and host architecture must be logged (e.g., `DOTNET_AOT_RID`).
- If containerized runs are added, base image + libc (glibc/musl) must be documented.
