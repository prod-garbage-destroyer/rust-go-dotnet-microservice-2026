#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <seeded-user-ids-comma-separated> [output-root] [run-id]"
  echo "example: $0 11111111-1111-1111-1111-111111111111"
  exit 1
fi

BENCH_USER_IDS="$1"
OUTPUT_ROOT="${2:-bench/results}"
RUN_ID="${3:-$(date +%Y%m%d-%H%M%S)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_RUST="${RUN_RUST:-true}"
RUN_GO="${RUN_GO:-true}"
RUN_DOTNET_JIT="${RUN_DOTNET_JIT:-true}"
RUN_DOTNET_AOT="${RUN_DOTNET_AOT:-true}"

RUST_BASE_URL="${RUST_BASE_URL:-http://localhost:3001}"
GO_BASE_URL="${GO_BASE_URL:-http://localhost:3002}"

DOTNET_JIT_TARGET_NAME="${DOTNET_JIT_TARGET_NAME:-dotnet-jit}"
DOTNET_AOT_TARGET_NAME="${DOTNET_AOT_TARGET_NAME:-dotnet-aot}"
DOTNET_JIT_PORT="${DOTNET_JIT_PORT:-3003}"
DOTNET_AOT_PORT="${DOTNET_AOT_PORT:-3004}"
DOTNET_DATABASE_URL="${DOTNET_DATABASE_URL:-Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1"
    exit 1
  fi
}

USE_PODMAN_BENCH="${USE_PODMAN_BENCH:-false}"
USE_PODMAN_DOTNET="${USE_PODMAN_DOTNET:-false}"
DOTNET_CONTAINER_ENGINE="${DOTNET_CONTAINER_ENGINE:-podman}"

if [ "$USE_PODMAN_BENCH" = "true" ]; then
  require_cmd podman
else
  require_cmd wrk
  require_cmd k6
fi
require_cmd curl
require_cmd python3

if [ "$USE_PODMAN_DOTNET" = "true" ]; then
  require_cmd "$DOTNET_CONTAINER_ENGINE"
fi

if [ "$USE_PODMAN_DOTNET" != "true" ] && ([ "$RUN_DOTNET_JIT" = "true" ] || [ "$RUN_DOTNET_AOT" = "true" ]); then
  require_cmd dotnet
fi

TARGET_MAPPINGS=()

echo "run-id: $RUN_ID"
echo "output-root: $OUTPUT_ROOT"
echo "use-podman-bench: $USE_PODMAN_BENCH"
echo "use-podman-dotnet: $USE_PODMAN_DOTNET"
echo "dotnet-container-engine: $DOTNET_CONTAINER_ENGINE"

if [ "$RUN_RUST" = "true" ]; then
  echo "[matrix] running rust-axum via run-v2-all"
  "$PROJECT_ROOT/bench/scripts/run-v2-all.sh" \
    "rust-axum" \
    "$RUST_BASE_URL" \
    "$BENCH_USER_IDS" \
    "$OUTPUT_ROOT" \
    "$RUN_ID"
  TARGET_MAPPINGS+=("rust-axum=$OUTPUT_ROOT/rust-axum/$RUN_ID")
fi

if [ "$RUN_GO" = "true" ]; then
  echo "[matrix] running go-fiber via run-v2-all"
  "$PROJECT_ROOT/bench/scripts/run-v2-all.sh" \
    "go-fiber" \
    "$GO_BASE_URL" \
    "$BENCH_USER_IDS" \
    "$OUTPUT_ROOT" \
    "$RUN_ID"
  TARGET_MAPPINGS+=("go-fiber=$OUTPUT_ROOT/go-fiber/$RUN_ID")
fi

if [ "$RUN_DOTNET_JIT" = "true" ]; then
  echo "[matrix] running dotnet jit lane"
  "$PROJECT_ROOT/bench/scripts/run-dotnet-lane-v2-all.sh" \
    "jit" \
    "$DOTNET_JIT_TARGET_NAME" \
    "$DOTNET_JIT_PORT" \
    "$BENCH_USER_IDS" \
    "$DOTNET_DATABASE_URL" \
    "$OUTPUT_ROOT" \
    "$RUN_ID"
  TARGET_MAPPINGS+=("$DOTNET_JIT_TARGET_NAME=$OUTPUT_ROOT/$DOTNET_JIT_TARGET_NAME/$RUN_ID")
fi

if [ "$RUN_DOTNET_AOT" = "true" ]; then
  echo "[matrix] running dotnet aot lane"
  "$PROJECT_ROOT/bench/scripts/run-dotnet-lane-v2-all.sh" \
    "aot" \
    "$DOTNET_AOT_TARGET_NAME" \
    "$DOTNET_AOT_PORT" \
    "$BENCH_USER_IDS" \
    "$DOTNET_DATABASE_URL" \
    "$OUTPUT_ROOT" \
    "$RUN_ID"
  TARGET_MAPPINGS+=("$DOTNET_AOT_TARGET_NAME=$OUTPUT_ROOT/$DOTNET_AOT_TARGET_NAME/$RUN_ID")
fi

if [ "${#TARGET_MAPPINGS[@]}" -eq 0 ]; then
  echo "no targets were enabled; nothing to aggregate"
  exit 1
fi

echo "[matrix] aggregating results"
"$PROJECT_ROOT/bench/scripts/aggregate-v2-results.sh" "artifacts" "${TARGET_MAPPINGS[@]}"

echo "matrix complete"
echo "aggregated benchmark: $PROJECT_ROOT/artifacts/benchmark-results-v2.json"
echo "aggregated charts: $PROJECT_ROOT/artifacts/charts-data-v2.json"
