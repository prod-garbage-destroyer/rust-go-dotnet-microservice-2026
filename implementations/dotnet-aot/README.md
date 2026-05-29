# dotnet-aot
ASP.NET Minimal API (.NET 10) microservice compiled with Native AOT — the fast-lane .NET configuration.

## Stack
- **Language:** C# / .NET 10
- **Framework:** ASP.NET Minimal API
- **Runtime:** Native AOT (self-contained, no JIT)
- **DB Driver:** Npgsql 10.0.2

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
cd microservice
export DATABASE_URL="Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench"
export PORT=3004
dotnet publish -c Release -o publish
./publish/microservice
```

Note: Native AOT compile time is significantly longer than JIT. Expect 30–60s publish time depending on machine.

## Container
Base image: `mcr.microsoft.com/dotnet/runtime-deps:10.0` (no .NET runtime needed — fully self-contained native binary).
