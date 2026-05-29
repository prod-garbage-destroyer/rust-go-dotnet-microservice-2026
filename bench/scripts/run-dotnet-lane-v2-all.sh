#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: $0 <jit|aot> <target-name> <port> <seeded-user-ids-comma-separated> [database-url] [output-root] [run-id]"
  echo "example: $0 jit dotnet-jit 3003 11111111-1111-1111-1111-111111111111"
  exit 1
fi

LANE="$1"
TARGET_NAME="$2"
PORT="$3"
BENCH_USER_IDS="$4"
DATABASE_URL="${5:-Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench}"
OUTPUT_ROOT="${6:-bench/results}"
RUN_ID="${7:-$(date +%Y%m%d-%H%M%S)}"
USE_PODMAN_DOTNET="${USE_PODMAN_DOTNET:-false}"
DOTNET_CONTAINER_ENGINE="${DOTNET_CONTAINER_ENGINE:-podman}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PUBLISH_DIR="$($PROJECT_ROOT/bench/scripts/build-dotnet-lane.sh "$LANE")"

PID_FILE="$PROJECT_ROOT/$OUTPUT_ROOT/$TARGET_NAME/$RUN_ID/dotnet.pid"
mkdir -p "$(dirname "$PID_FILE")"

pid="$($PROJECT_ROOT/bench/scripts/start-dotnet-lane.sh "$LANE" "$PUBLISH_DIR" "$PORT" "$DATABASE_URL" "$PID_FILE")"

cleanup() {
  if [ "$USE_PODMAN_DOTNET" = "true" ]; then
    "$DOTNET_CONTAINER_ENGINE" rm -f "$pid" >/dev/null 2>&1 || true
  else
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  fi
}
trap cleanup EXIT

for _ in $(seq 1 40); do
  if curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if ! curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; then
  echo "service did not become healthy on port $PORT"
  exit 1
fi

"$PROJECT_ROOT/bench/scripts/run-v2-all.sh" "$TARGET_NAME" "http://localhost:$PORT" "$BENCH_USER_IDS" "$OUTPUT_ROOT" "$RUN_ID"

echo "dotnet lane run complete: lane=$LANE target=$TARGET_NAME run-id=$RUN_ID"
