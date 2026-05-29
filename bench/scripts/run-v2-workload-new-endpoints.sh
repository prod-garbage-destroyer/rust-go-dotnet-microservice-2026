#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <target-name> <base-url> [output-root] [run-id]"
  echo "example: $0 rust-axum http://localhost:3001"
  exit 1
fi

TARGET_NAME="$1"
BASE_URL="$2"
OUTPUT_ROOT="${3:-bench/results}"
RUN_ID="${4:-$(date +%Y%m%d-%H%M%S)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="$PROJECT_ROOT/$OUTPUT_ROOT/$TARGET_NAME/$RUN_ID"
mkdir -p "$RUN_DIR"

run_and_capture() {
  local label="$1"
  local file_name="$2"
  shift 2

  echo "$label"
  "$@" | tee "$RUN_DIR/$file_name"
}

run_and_capture "[warmup] GET /health c=50 d=10s" "warmup-health-new-endpoints.txt" \
  wrk -c 50 -d 10s -t 4 "$BASE_URL/health"

run_and_capture "[warmup] POST /json/roundtrip c=100 d=10s" "warmup-json-roundtrip.txt" \
  wrk -c 100 -d 10s -t 8 -s "$PROJECT_ROOT/bench/wrk/json-roundtrip.lua" "$BASE_URL"

run_and_capture "[warmup] POST /crypto/hash c=50 d=10s" "warmup-crypto-hash.txt" \
  wrk -c 50 -d 10s -t 8 -s "$PROJECT_ROOT/bench/wrk/crypto-hash.lua" "$BASE_URL"

run_and_capture "[json] POST /json/roundtrip c=100 d=30s" "json-roundtrip-c100.txt" \
  wrk -c 100 -d 30s -t 8 -s "$PROJECT_ROOT/bench/wrk/json-roundtrip.lua" "$BASE_URL"

run_and_capture "[cpu] POST /crypto/hash c=50 d=30s" "crypto-hash-c50.txt" \
  wrk -c 50 -d 30s -t 8 -s "$PROJECT_ROOT/bench/wrk/crypto-hash.lua" "$BASE_URL"

echo "new endpoint workload outputs: $RUN_DIR"
