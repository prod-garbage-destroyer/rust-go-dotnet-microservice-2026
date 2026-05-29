# Benchmark Harness (v2)

This directory contains versioned benchmark scripts so runs are reproducible and reviewable in git.

## wrk scripts
- `wrk/get-users.lua`: GET `/users/:id` requests against pre-seeded IDs.
- `wrk/post-users.lua`: POST `/users` with unique generated emails.
- `wrk/json-roundtrip.lua`: POST `/json/roundtrip` JSON-heavy request payload.
- `wrk/crypto-hash.lua`: POST `/crypto/hash` CPU-heavy hash payload.

## k6 scripts
- `k6/tail-latency.js`: open-loop tail-latency benchmark using staged arrival rates.
- `k6/scenarios/pool-saturation-recovery.js`: closed-loop saturation ladder with recovery observation window.

## helpers
- `scripts/run-v2-baseline.sh`: runs warmup/read/write wrk phases and stores raw outputs.
- `scripts/collect-metrics.sh`: parses wrk outputs into normalized JSON metrics.
- `scripts/run-k6-tail-latency.sh`: runs k6 open-loop tail-latency scenario and exports normalized metrics.
- `scripts/run-k6-pool-saturation-recovery.sh`: runs k6 saturation/recovery scenario and exports normalized metrics.
- `scripts/collect-k6-metrics.sh`: normalizes k6 summary JSON into video/report-friendly metrics.
- `scripts/run-v2-all.sh`: runs wrk baseline + both k6 scenarios and writes merged `benchmark-results-v2.json`.
- `scripts/run-v2-workload-new-endpoints.sh`: runs wrk benchmarks for JSON-heavy and CPU-heavy endpoints.
- `scripts/build-dotnet-lane.sh`: builds dotnet `jit` or `aot` publish outputs.
- `scripts/start-dotnet-lane.sh`: starts dotnet `jit` or `aot` publish artifact on a port.
- `scripts/run-dotnet-lane-v2-all.sh`: end-to-end lane run for `dotnet-jit` or `dotnet-aot` with `run-v2-all.sh`.
- `scripts/run-v2-matrix.sh`: runs enabled targets (Rust, Go, .NET JIT, .NET AOT) and aggregates final v2 artifacts.
- `scripts/run-v3-podman.sh`: fully containerized v3 run using Podman compose profiles.

## Podman benchmark mode

If `wrk` and `k6` are not installed on the host, you can run them via Podman containers:

```bash
USE_PODMAN_BENCH=true \
bench/scripts/run-v2-matrix.sh "11111111-1111-1111-1111-111111111111"
```

Preflight check before full run:

```bash
bench/scripts/podman-preflight.sh http://localhost:3001
```

Notes:
- In Podman mode, benchmark tools target `host.containers.internal` automatically.
- Service processes still run on the host (or via existing lane scripts), while load tools run in containers.
- Optional image overrides:
  - `PODMAN_WRK_IMAGE` (default `auto`, builds local arm64 wrk image)
  - `PODMAN_K6_IMAGE` (default `docker.io/grafana/k6:latest`)
  - `PODMAN_WRK_CONTAINERFILE` (default `bench/podman/wrk/Containerfile`)
  - `PODMAN_WRK_LOCAL_IMAGE` (default `local/bench-wrk:arm64`)

### v3 containerized targets

- `official`: `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot` (recommended publish set)
- `all`: full matrix including `dotnet-jit`; lane failures are reported and run continues

```bash
bench/scripts/run-v3-podman.sh official
```

```bash
bench/scripts/run-v3-podman.sh all
```

## Environment variables
- `BENCH_USER_IDS`: comma-separated UUIDs for `get-users.lua`.
- `BENCH_NOTIFY_LOG`: set to `false` to disable async notification logs during timed runs.

## Example commands

```bash
export BENCH_NOTIFY_LOG=false
export BENCH_USER_IDS="id1,id2,id3"
wrk -c 200 -d 30s -t 8 -s bench/wrk/get-users.lua http://localhost:3001
wrk -c 50 -d 20s -t 4 -s bench/wrk/post-users.lua http://localhost:3001
```

```bash
bench/scripts/run-v2-baseline.sh rust-axum http://localhost:3001 \
  "11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222"
```

```bash
BASE_URL=http://localhost:3001 \
BENCH_USER_IDS="11111111-1111-1111-1111-111111111111" \
k6 run --summary-export bench/results/rust-axum/tail-summary.json \
  bench/k6/tail-latency.js
```

```bash
bench/scripts/run-k6-tail-latency.sh rust-axum http://localhost:3001 \
  "11111111-1111-1111-1111-111111111111"
```

```bash
bench/scripts/run-k6-pool-saturation-recovery.sh rust-axum http://localhost:3001 \
  "11111111-1111-1111-1111-111111111111"
```

```bash
bench/scripts/run-v2-all.sh rust-axum http://localhost:3001 \
  "11111111-1111-1111-1111-111111111111"
```

```bash
bench/scripts/run-v2-workload-new-endpoints.sh rust-axum http://localhost:3001
```

```bash
bench/scripts/run-dotnet-lane-v2-all.sh jit dotnet-jit 3003 \
  "11111111-1111-1111-1111-111111111111"
```

```bash
DOTNET_AOT_RID=osx-arm64 \
bench/scripts/run-dotnet-lane-v2-all.sh aot dotnet-aot 3004 \
  "11111111-1111-1111-1111-111111111111"
```

```bash
bench/scripts/run-v2-matrix.sh "11111111-1111-1111-1111-111111111111"
```

Optional target toggles:

```bash
RUN_GO=false RUN_DOTNET_AOT=false \
bench/scripts/run-v2-matrix.sh "11111111-1111-1111-1111-111111111111"
```
