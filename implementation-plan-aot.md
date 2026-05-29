# AOT-First Containerized Benchmark Plan (Podman Canonical)

## Summary
- Goal: deliver a defensible benchmark where `dotnet-aot` is the official C# lane, fully containerized, reproducible, and comparable against `rust-axum`, `go-fiber`, and `go-nethttp-chi`.
- Publication policy: if `dotnet-jit` fails on this host, do not block release; document it as host/runtime incompatibility and keep `dotnet-aot` as the official C# result.
- Plan persistence target: this file (`implementation-plan-aot.md`) is the canonical execution plan document.

## Implementation Changes
1. Lock Podman as canonical orchestration path.
- Keep `bench/podman/compose.yaml` as source of truth for service topology, DB, ports, and environment.
- Keep benchmark runner entrypoint as `bench/scripts/run-v3-podman.sh`.
- Ensure `run-v3-podman.sh` can run `dotnet-aot` independently and in full matrix mode without requiring `dotnet-jit` success.

2. Finalize AOT build/run pipeline.
- Keep multi-stage AOT container flow (`sdk` builder -> `runtime-deps` runtime) for `dotnet-aot` service image.
- Keep lane-specific build selection in `bench/scripts/build-dotnet-lane.sh`:
  - `jit` -> `implementations/dotnet-minimal/microservice`
  - `aot` -> `implementations/dotnet-aot/microservice`
- Keep Darwin local AOT fallback behavior in script (`LIBRARY_PATH` enrichment for OpenSSL/Brotli) for local smoke/debug builds.

3. Stabilize fairness controls for official runs.
- Use identical load profiles, seed logic, DB target, and warmup/measurement windows for all official lanes.
- Keep runtime knobs explicit and versioned in scripts/manifests (ports, pool sizes, notify logging off, image tags).
- Keep same result schema and output directories under `bench/results/*` for all lanes.

4. Result policy + artifact completeness.
- Official comparison set: `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot`.
- `dotnet-jit` is appendix-only if unstable in environment (include error signature + host details + reproduction command).
- Produce a single summary artifact set containing:
  - raw benchmark outputs,
  - normalized metrics,
  - environment/runtime metadata,
  - concise fairness checklist,
  - final verdict JSON/markdown.

5. Narrative alignment (for video and README/docs).
- Lead with “AOT-focused fairness response.”
- State that C# number shown is `dotnet-aot` under identical containerized conditions.
- State `dotnet-jit` exclusion reason as compatibility, not performance claim.
- Make conclusions environment-scoped and avoid universal claims.

## Public Interfaces / Behavior Changes
- `bench/scripts/build-dotnet-lane.sh`
  - Behavior: lane-specific project source and Darwin AOT linker-path handling remain explicit defaults.
- `bench/scripts/run-v3-podman.sh`
  - Behavior: official run mode treats `dotnet-aot` as required; `dotnet-jit` failure should not invalidate AOT-focused publication.
- Benchmark publication behavior
  - Official C# lane in produced summaries/verdict artifacts is `dotnet-aot`.

## Test Plan
1. Build verification.
- `bash -n` for benchmark scripts.
- `build-dotnet-lane.sh jit` succeeds to clean temp output root.
- `build-dotnet-lane.sh aot` succeeds in canonical container build path.

2. Runtime smoke.
- Start PostgreSQL + each official lane via Podman compose profiles.
- Health checks pass for all official lanes.
- Minimal endpoint smoke (`/health`, read/write path) passes for each official lane.

3. Fairness/run integrity.
- Run `run-v3-podman.sh` for each official lane and full official matrix.
- Confirm output files exist and schema fields are populated consistently.
- Confirm summary excludes `dotnet-jit` from official ranking when failed, but includes failure diagnostics in appendix metadata.

4. Regression checks.
- Ensure no script path regresses to building AOT from `dotnet-minimal`.
- Ensure result aggregation still handles existing historical lanes without schema breakage.

## Assumptions and Defaults
- Primary runtime: `Podman`.
- Official C# lane policy: `AOT-only official results` when JIT remains unstable on this host.
- `dotnet-jit` remains optional/diagnostic for this environment and non-blocking for publication.
