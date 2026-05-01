# Fairness Policy — Rust vs Go vs ASP.NET Microservice Benchmark 2026

## Same Functionality
Every implementation satisfies the same spec (`spec.yaml`):
- 5 endpoints: POST /users, GET /users/:id, GET /users, DELETE /users/:id, GET /health
- Identical PostgreSQL schema (UUID primary key, unique email index)
- Async background job triggered on user creation (non-blocking, logged)
- Input validation: name (required, 1–100 chars), email (required, valid format)

## Same External Dependencies
- Database: PostgreSQL 16 (single shared instance via Podman)
- No Redis, no message queues — same zero additional infra for all targets
- Network: same Podman network (`bench-net`), same hostname resolution
- All targets use environment variable `DATABASE_URL` to connect

## Same Hardware Constraints
- All implementations run on the same machine (macOS, Apple Silicon M-series)
- No container CPU/memory limits imposed — all targets share the same host resources equally
- Benchmarks run sequentially (one target at a time) to avoid resource contention

## Same Connection Pool
- All implementations use a connection pool: min=5, max=20
- Connection pools are initialized at startup before the first benchmark request
- Rust: `sqlx` pool, Go: `pgxpool`, ASP.NET: Npgsql NpgsqlDataSource with pooling

## Same Warmup
- Before each measurement phase, every target receives a 10-second warmup at 50 concurrent connections against `GET /health`
- Warmup data is discarded and not included in measurements
- Services are restarted fresh before each benchmark run

## Same Workload
- wrk benchmark tool (version 4.2.0) used for all targets
- Identical concurrency levels: 50, 200, 500
- Identical duration: 30 seconds per phase
- Identical request mix per Lua script: 70% GET /users/:id (random pre-seeded ID), 30% POST /users

## Same Retry Policy
- Maximum 1 retry per failed benchmark run
- All retries are recorded in `benchmark-results.json` under `notes`
- A run is retried only for infrastructure failures (port not ready, DB connection timeout), not for performance reasons

## Optimization Policy
**Idiomatic optimizations are allowed and applied symmetrically:**
- Connection pooling: applied to all three (see above)
- Async/non-blocking I/O: each target uses its idiomatic async runtime (Tokio for Rust, goroutines for Go, async/await for ASP.NET)
- JSON serialization: each target uses its idiomatic fast serializer (serde_json, encoding/json, System.Text.Json)
- No special compiler flags that are not the default release/production build flags

**Not applied:**
- No unsafe Rust tricks beyond the framework's default
- No CGO for Go
- No AOT compilation for .NET (standard JIT release build)
- No hand-tuned kernel parameters

## What Counts as a Fair Run
- All endpoints return correct HTTP status codes per spec
- All endpoints return the declared JSON shape
- POST /users inserts a row and triggers the async job
- GET /users/:id returns 404 for unknown UUIDs
- DELETE /users/:id returns 204 and removes the row

**Implementations that fail functional tests are excluded from benchmarks and reported as failed.**

## Known Asymmetries
- .NET has a JIT warm-up cost; this is accounted for by the warmup phase and cold-start measurement being separate
- Rust produces a single native binary; Go produces a single native binary; .NET runs on the CLR — this is an inherent property of each stack and is reported, not corrected for
- Build times vary significantly due to language design; this is measured and reported as a fair metric
