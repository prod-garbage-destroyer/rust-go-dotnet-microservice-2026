#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <target> [output-root]"
  echo ""
  echo "targets:"
  echo "  rust-axum        (port 3001)"
  echo "  go-fiber         (port 3002)"
  echo "  go-nethttp-chi   (port 3005)"
  echo "  dotnet-jit       (port 3003)"
  echo "  dotnet-aot       (port 3004)"
  echo "  all              (sequentially run all 5)"
  echo ""
  echo "required env: BENCH_USER_IDS (comma-separated UUIDs)"
  echo "optional env: USE_PODMAN_BENCH=true, K6_ALLOW_THRESHOLD_FAILURE=true"
  exit 1
fi

TARGET="$1"
OUTPUT_ROOT="${2:-bench/results}"
BENCH_USER_IDS="${BENCH_USER_IDS:-}"

if [ -z "$BENCH_USER_IDS" ]; then
  echo "error: BENCH_USER_IDS must be set (comma-separated seeded UUIDs)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

declare -A TARGET_PORTS
TARGET_PORTS["rust-axum"]="3001"
TARGET_PORTS["go-fiber"]="3002"
TARGET_PORTS["go-nethttp-chi"]="3005"
TARGET_PORTS["dotnet-jit"]="3003"
TARGET_PORTS["dotnet-aot"]="3004"

run_target() {
  local name="$1"
  local port="${TARGET_PORTS[$name]}"
  local base_url="http://localhost:${port}"

  echo ""
  echo "============================================================"
  echo "  v3 benchmark: $name (port $port)"
  echo "============================================================"

  if ! curl -fsS "$base_url/health" >/dev/null 2>&1; then
    echo "error: $name not reachable at $base_url/health"
    echo "start it first, then re-run:"
    echo "  cd implementations/$name && <build+run commands>"
    exit 1
  fi

  "$SCRIPT_DIR/run-v2-all.sh" "$name" "$base_url" "$BENCH_USER_IDS" "$OUTPUT_ROOT"

  echo ""
  echo "  v3 complete: $name"
}

if [ "$TARGET" = "all" ]; then
  for name in rust-axum go-fiber go-nethttp-chi dotnet-jit dotnet-aot; do
    run_target "$name"
  done
  echo ""
  echo "============================================================"
  echo "  v3 all targets complete"
  echo "  output: $PROJECT_ROOT/$OUTPUT_ROOT"
  echo "============================================================"
else
  if [ -z "${TARGET_PORTS[$TARGET]:-}" ]; then
    echo "error: unknown target '$TARGET'. valid: ${!TARGET_PORTS[*]}"
    exit 1
  fi
  run_target "$TARGET"
fi
