# rust-axum

Rust + Axum 0.8 microservice implementation for the `rust-go-dotnet-microservice-2026` experiment.

## Stack
- **Language:** Rust 1.93.1
- **Framework:** Axum 0.8.9
- **DB Driver:** `tokio-postgres` + `deadpool-postgres`, with typed queries generated at dev-time by [cornucopia](https://github.com/cornucopia-rs/cornucopia) from `queries/users.sql` (committed under `codegen/`)
- **Validation:** validator 0.18
- **Runtime:** Tokio

### Why not sqlx?

The original implementation used `sqlx`. Profiling showed `sqlx`'s connection pool pings the
database on every single connection acquire (`test_before_acquire`, default `true`) **and**
unconditionally on every release (`PoolConnection::drop` → `return_to_pool` → `raw.ping()`,
not configurable) — up to 3 round trips to Postgres per request instead of 1. This made the
sqlx version slower than the Go implementation despite Rust having no GC and a leaner runtime.

`tokio-postgres` + `deadpool-postgres` (default `RecyclingMethod::Fast`, a pure in-memory
`is_closed()` check, no network I/O) avoids both pings entirely. `cornucopia` restores sqlx's
headline feature — compile-time, real-schema-checked queries — as a dev-time code generator
on top of that same driver, so there's no runtime cost for the type safety.

Benchmarked head-to-head against this repo's Go/Fiber implementation on the same Postgres
instance (wrk, GET /users/:id): **+37% RPS at c=50, +28% at c=200, +21% at c=500** in favor
of Rust — reversing the original result where Rust trailed Go.

To regenerate the typed queries after editing `queries/users.sql`:
```bash
cornucopia live "$DATABASE_URL" -q queries -d codegen
```

## Endpoints
- `GET /health` → `{"status":"ok"}`
- `POST /users` → 201 + user object
- `GET /users/:id` → 200 or 404
- `GET /users` → 200 array
- `DELETE /users/:id` → 204 or 404

## Run

```bash
export DATABASE_URL=postgres://bench:bench@localhost:5433/bench
export PORT=3001
cargo build --release
./target/release/microservice
```

## Test

```bash
curl http://localhost:3001/health
curl -X POST http://localhost:3001/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'
```

## Build Stats (measured, post-cornucopia-migration)
- Cold build: ~25 seconds (was ~46s with sqlx)
- Binary size: ~3.0 MB (self-contained)
- Dependencies: ~155 crates (was 267 with sqlx)
