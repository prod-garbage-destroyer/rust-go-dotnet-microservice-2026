# go-fiber

Go + Fiber v2 microservice implementation for the `rust-go-dotnet-microservice-2026` experiment.

## Stack
- **Language:** Go 1.26.2
- **Framework:** Fiber v2 (fasthttp-based)
- **DB Driver:** pgx v5.9.2 with pgxpool
- **Validation:** go-playground/validator v10

## Endpoints
- `GET /health` → `{"status":"ok"}`
- `POST /users` → 201 + user object
- `GET /users/:id` → 200 or 404
- `GET /users` → 200 array
- `DELETE /users/:id` → 204 or 404

## Run

```bash
export DATABASE_URL=postgres://bench:bench@localhost:5433/bench
export PORT=3002
go build -o microservice .
./microservice
```

## Test

```bash
curl http://localhost:3002/health
curl -X POST http://localhost:3002/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob","email":"bob@example.com"}'
```

## Build Stats (measured)
- Cold build: ~300ms
- Binary size: 20.3 MB (includes Go runtime)
- Dependencies: 18 modules
