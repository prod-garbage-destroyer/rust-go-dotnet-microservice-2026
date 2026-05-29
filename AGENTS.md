# v3 Benchmark — Current State (May 23, 2026)

## Goal
Definitive fair benchmark: Rust Axum vs Go Fiber vs Go net/http+chi vs .NET JIT vs .NET AOT — answering every fairness critique from issue #1.

## Branch
`rust-go-dotnet-microservice-2026-v3`

## Progress

### Completed
- All 5 implementations fixed/created with code fairness fixes
- All 5 container images built (bench/podman/services/)
- podman-compose.yaml with profiles, PostgreSQL 16, health checks
- Orchestrator script: `bench/scripts/run-v3-podman.sh`
- `.dockerignore` added to exclude obj/bin/target from build context
- Schema creation + user seeding added to orchestrator

### Benchmark Results (macOS podman VM — 2x overhead vs bare-metal)
| Target | Status | Notes |
|---|---|---|
| rust-axum | ✅ Completed | ~24k RPS reads, ~15k RPS writes |
| go-fiber | ✅ Completed |  |
| go-nethttp-chi | ✅ Completed |  |
| dotnet-jit | ❌ Crashes | SIGILL (exit 132) on Npgsql endpoint under load |
| dotnet-aot | ✅ Completed | 6.4M k6 iterations, 18k/s, p(99)=49ms |

### dotnet-jit Issue
- .NET 10 JIT on podman Fedora ARM64 VM crashes with SIGILL on Npgsql DB endpoints under concurrent load
- Health endpoint works fine (33k RPS), DB queries crash
- Native AOT variant works perfectly (same code, same Npgsql version)
- Likely a .NET 10 JIT code-gen issue with this specific kernel/VM combination
- Env vars that helped health endpoint but didn't fix DB: `DOTNET_EnableHWIntrinsic=0`, `DOTNET_EnableARM64JittedIntrinsics=0`, `DOTNET_TieredCompilation=0`, `DOTNET_GCName=libclrgc.so`
- These are baked into `bench/podman/services/dotnet-jit.Containerfile` as ENV

### Known Issues Found & Fixed
1. Rust DATABASE_URL in compose.yaml was Npgsql format (`Host=...;`) — fixed to `postgres://bench:bench@...`
2. bash 3.2 compat: `declare -A` replaced with `get_port()` function
3. Missing schema creation before seeding added
4. podman-compose (Python) doesn't support `rm` subcommand — stop/rm rewritten to direct `podman stop/rm`
5. podman-compose doesn't pass compose env vars with semicolons correctly — DATABASE_URL was missing in compose-created containers
6. dotnet-aot ENTRYPOINT needed full path `/app/microservice`
7. .NET 10 images use Ubuntu Noble (not Bookworm) — `libgssapi-krb5-2` needed for Npgsql

### Results Location
`bench/results/<target>/v3-*timestamp*-<target>/`

## Next Steps

### 1. Get Production Numbers
Run on bare-metal Linux host (not macOS podman VM):
```bash
git checkout rust-go-dotnet-microservice-2026-v3
# Build&run all:
./bench/scripts/run-v3-podman.sh all
```
Or use host-native runner (if tools installed):
```bash
./bench/scripts/run-v3.sh rust-axum
```

### 2. Video Production
- Create `video-data.ts` for v3 "definitive fair benchmark" slug
- Write narration script (acknowledge issue #1 criticism, show AOT numbers, compare go-nethttp-chi vs go-fiber, final verdict)
- Load skill: `video/video-creator` for Remotion composition
- Generate TTS audio via `video/audio-creator`
- Render 4K MP4
- Generate `output/<slug>/info.md` with YouTube metadata

### 3. Fairness Documentation
- `fairness-policy-v3.md` exists with Known Asymmetries documented
- Add note about dotnet-jit SIGILL and AOT-as-representative rationale
- Results only meaningful from bare-metal Linux run
