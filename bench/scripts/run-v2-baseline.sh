#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <target-name> <base-url> <seeded-user-ids-comma-separated> [output-root]"
  echo "example: $0 rust-axum http://localhost:3001 11111111-1111-1111-1111-111111111111"
  exit 1
fi

TARGET_NAME="$1"
BASE_URL="$2"
BENCH_USER_IDS="$3"
OUTPUT_ROOT="${4:-bench/results}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$PROJECT_ROOT/$OUTPUT_ROOT/$TARGET_NAME/$TIMESTAMP"
mkdir -p "$RUN_DIR"

export BENCH_USER_IDS
export BENCH_NOTIFY_LOG="false"

run_and_capture() {
  local label="$1"
  local file_name="$2"
  shift 2

  echo "$label"
  "$@" | tee "$RUN_DIR/$file_name"
}

run_and_capture "[warmup] GET /health c=50 d=10s" "warmup-health.txt" \
  wrk -c 50 -d 10s -t 4 "$BASE_URL/health"

run_and_capture "[read] GET /users/:id c=50 d=30s" "read-c50.txt" \
  wrk -c 50 -d 30s -t 8 -s "$PROJECT_ROOT/bench/wrk/get-users.lua" "$BASE_URL"

run_and_capture "[read] GET /users/:id c=200 d=30s" "read-c200.txt" \
  wrk -c 200 -d 30s -t 8 -s "$PROJECT_ROOT/bench/wrk/get-users.lua" "$BASE_URL"

run_and_capture "[read] GET /users/:id c=500 d=30s" "read-c500.txt" \
  wrk -c 500 -d 30s -t 8 -s "$PROJECT_ROOT/bench/wrk/get-users.lua" "$BASE_URL"

run_and_capture "[write] POST /users c=50 d=20s" "write-c50.txt" \
  wrk -c 50 -d 20s -t 4 -s "$PROJECT_ROOT/bench/wrk/post-users.lua" "$BASE_URL"

"$PROJECT_ROOT/bench/scripts/collect-metrics.sh" \
  "$TARGET_NAME" \
  "$RUN_DIR" \
  "$RUN_DIR/benchmark-results.json"

echo "run outputs: $RUN_DIR"
