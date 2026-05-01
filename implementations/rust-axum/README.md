# rust-axum

Rust + Axum 0.8 microservice implementation for the `rust-go-dotnet-microservice-2026` experiment.

## Stack
- **Language:** Rust 1.93.1
- **Framework:** Axum 0.8.9
- **DB Driver:** sqlx 0.8.6 (async, compile-time checked queries)
- **Validation:** validator 0.18
- **Runtime:** Tokio

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

## Build Stats (measured)
- Cold build: ~46 seconds
- Incremental: ~0.4 seconds
- Binary size: 4.1 MB (self-contained)
- Dependencies: 267 crates
