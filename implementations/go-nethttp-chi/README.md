# go-nethttp-chi

Go `net/http` + `chi` router microservice — the stdlib-tier Go lane for the v3 benchmark.

## Stack
- **Language:** Go 1.26.2
- **Framework:** `net/http` (stdlib) + `chi` v5 router
- **DB Driver:** `pgx` v5 with `pgxpool`

## Why this lane exists
The v2 benchmark used Fiber (fasthttp), which is explicitly non-stdlib and trades HTTP/2 support + correct connection handling for raw speed. This lane uses the idiomatic Go equivalent of Axum/Kestrel — `net/http` + a lightweight router — for an apples-to-apples framework-class comparison.

See `fairness-policy-v3.md` §Known Asymmetries for context.

## Endpoints
- `GET /health` → `{"status":"ok"}`
- `POST /json/roundtrip` → JSON decode/encode + aggregation
- `POST /crypto/hash` → CPU-bound SHA-256 hashing
- `POST /users` → 201 + user object
- `GET /users/{id}` → 200 or 404
- `GET /users` → 200 array
- `DELETE /users/{id}` → 204 or 404

## Run

```bash
export DATABASE_URL="postgres://bench:bench@localhost:5432/bench"
export PORT=3005
go build -o microservice .
./microservice
```
