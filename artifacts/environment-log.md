# Environment Actions Log

**Experiment:** rust-go-dotnet-microservice-2026
**Date:** 2026-05-01

## Infrastructure Created

### Podman Network
```
podman network create bench-net
```
Network: `bench-net`

### PostgreSQL 16 Container
```
podman run -d \
  --name bench-postgres \
  --network bench-net \
  -e POSTGRES_USER=bench \
  -e POSTGRES_PASSWORD=bench \
  -e POSTGRES_DB=bench \
  -p 5433:5432 \
  docker.io/postgres:16
```
- Container: `bench-postgres`
- Host port: `5433` (5432 was occupied by a local PostgreSQL instance)
- Verified ready: `pg_isready -U bench`

## Service Start Events

### rust-axum (port 3001)
```
DATABASE_URL=postgres://bench:bench@localhost:5433/bench PORT=3001 ./target/release/microservice
```
- PID recorded at runtime
- Startup time measured: 89ms to first health response

### go-fiber (port 3002)
```
DATABASE_URL=postgres://bench:bench@localhost:5433/bench PORT=3002 ./microservice
```
- Startup time measured: 89ms

### dotnet-minimal (port 3003)
```
DATABASE_URL="Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench" PORT=3003 dotnet publish/microservice.dll
```
- Startup time measured: 288ms

## Benchmark Commands

### Warmup (all targets)
```
wrk -c 50 -d 10s -t 4 http://localhost:<PORT>/health
```

### GET benchmark (c=50, c=200, c=500)
```
wrk -c <CONC> -d 30s -t 8 -s /tmp/bench-scripts/get-users.lua http://localhost:<PORT>
```
5 runs per concurrency level per target.

### POST benchmark (c=50)
```
wrk -c 50 -d 20s -t 4 -s /tmp/bench-scripts/post-users.lua http://localhost:<PORT>
```
5 runs per target.

## Teardown

```bash
# Kill all service processes
pkill -f "target/release/microservice"
pkill -f "go-fiber/microservice"
pkill -f "dotnet.*microservice.dll"

# Remove Podman container and network
podman rm -f bench-postgres
podman network rm bench-net
```

## Notes
- Port 5432 was occupied by a local macOS PostgreSQL instance; Podman container was mapped to 5433
- All services ran bare-metal (not in containers) for consistent host-level memory measurement
- Podman machine was pre-existing (`podman-machine-default`)
