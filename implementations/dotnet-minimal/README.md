# dotnet-minimal

ASP.NET Minimal API (.NET 10) microservice implementation for the `rust-go-dotnet-microservice-2026` experiment.

## Stack
- **Language:** C# / .NET 10.0.107
- **Framework:** ASP.NET Minimal API
- **DB Driver:** Npgsql 10.0.2

## Endpoints
- `GET /health` → `{"status":"ok"}`
- `POST /users` → 201 + user object
- `GET /users/{id}` → 200 or 404
- `GET /users` → 200 array
- `DELETE /users/{id}` → 204 or 404

## Run

```bash
cd microservice
export DATABASE_URL="Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench"
export PORT=3003
dotnet publish -c Release -o publish
dotnet publish/microservice.dll
```

## Test

```bash
curl http://localhost:3003/health
curl -X POST http://localhost:3003/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Carol","email":"carol@example.com"}'
```

## Build Stats (measured)
- Publish time: ~835ms
- Publish dir size: 1.6 MB (requires .NET 10 runtime installed, ~200 MB)
- Dependencies: 12 NuGet packages
