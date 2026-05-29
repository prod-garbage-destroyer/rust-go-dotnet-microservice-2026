# Experiment Summary v3

**Experiment slug:** `rust-go-dotnet-microservice-2026-v3`  
**Generated:** 2026-05-27T13:20:03Z  
**Official publish set:** `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot`

## Executive Read

- `rust-axum` leads closed-loop read throughput at c=200 with **22462.2 RPS**.
- `go-nethttp-chi` leads open-loop tail p99 with **108.58 ms**.
- `dotnet-aot` leads open-loop tail p99.9 with **260.49 ms**.
- `go-fiber` leads saturation recovery p99 with **60.26 ms**.
- `dotnet-aot` is the official C# lane and lands in the middle of the pack on throughput while staying competitive on tail metrics.
- `dotnet-jit` is excluded from official ranking on this host because the latest v3 run set never progressed beyond warmup artifacts.

## Key Metrics Snapshot

| Target | Read RPS c=200 | Write RPS c=50 | Tail p99 (k6) | Tail p99.9 (k6) | Recovery p99 (k6) |
|---|---:|---:|---:|---:|---:|
| rust-axum | 22462.2 | 12763.88 | 1078.29 ms | 1481.57 ms | 81.92 ms |
| go-fiber | 11982.2 | 10839.52 | 446.85 ms | 691.63 ms | 60.26 ms |
| go-nethttp-chi | 18759.85 | 7883.67 | 108.58 ms | 621.57 ms | 156.15 ms |
| dotnet-aot | 17283.2 | 7910.22 | 215.98 ms | 260.49 ms | 68.0 ms |

## Publish-Safe Claims

- In this run window, `rust-axum` is the highest-throughput official lane at c=200, ahead of `go-fiber` by 87.46%.
- `go-nethttp-chi` is the lowest-tail official lane on open-loop p99 (108.58 ms).
- `dotnet-aot` is the lowest-tail official lane on open-loop p99.9 (260.49 ms).
- `go-fiber` recovers fastest after pool saturation with p99 60.26 ms.
- `dotnet-aot` is the only official C# lane for v3 on this host; do not mix it with `dotnet-jit` in ranking claims.

## Provenance

- `rust-axum`: `bench/results/rust-axum/v3-20260526-212300-rust-axum`
- `go-fiber`: `bench/results/go-fiber/v3-20260526-213932-go-fiber`
- `go-nethttp-chi`: `bench/results/go-nethttp-chi/v3-20260526-215610-go-nethttp-chi`
- `dotnet-aot`: `bench/results/dotnet-aot/v3-20260526-210210-dotnet-aot`

## Missing From This Publish Cut

- `cpu-efficiency-v3.json` has not been generated because no `perf`-derived aggregate was present in the selected run window.
- `startup-cold-warm-v3.json` has not been generated because startup/cold-warm measurements were not aggregated into the chosen v3 official run set.
