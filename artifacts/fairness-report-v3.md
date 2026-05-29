# Fairness Report v3

- Official publish set: `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot`.
- Official C# lane: `dotnet-aot`.
- `dotnet-jit` is excluded from ranking on this host because it never produced a full merged v3 artifact.
- Warmup + timed run provenance comes from per-target `benchmark-results-v2.json` files in `bench/results/...`.
- Framework-class caveat remains: `go-fiber` is fasthttp-based and not stdlib-tier. Use `go-nethttp-chi` for apples-to-apples stdlib/Kestrel/Axum framing.

## Excluded Targets
- `dotnet-jit`: latest-v3-host-run-stopped-after-warmup-only-files-SIGILL-documented-in-project-AGENTS
