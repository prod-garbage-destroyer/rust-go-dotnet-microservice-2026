#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <target> [seed-count]"
  echo ""
  echo "targets:"
  echo "  rust-axum        (port 3001)"
  echo "  go-fiber         (port 3002)"
  echo "  go-nethttp-chi   (port 3005)"
  echo "  dotnet-jit       (port 3003)"
  echo "  dotnet-aot       (port 3004)"
  echo "  official         (official publish set: rust-axum, go-fiber, go-nethttp-chi, dotnet-aot)"
  echo "  all              (sequentially run all 5 — ~60-90 min)"
  echo ""
  echo "example: $0 go-fiber"
  exit 1
fi

TARGET="$1"
SEED_COUNT="${2:-20}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/bench/podman/compose.yaml"
OUTPUT_ROOT="$PROJECT_ROOT/bench/results"
OFFICIAL_TARGETS=(rust-axum go-fiber go-nethttp-chi dotnet-aot)
ALL_TARGETS=(rust-axum go-fiber go-nethttp-chi dotnet-jit dotnet-aot)
FAILED_TARGETS=()

get_port() {
  case "$1" in
    rust-axum) echo "3001" ;;
    go-fiber) echo "3002" ;;
    go-nethttp-chi) echo "3005" ;;
    dotnet-jit) echo "3003" ;;
    dotnet-aot) echo "3004" ;;
    *) echo "" ;;
  esac
}

echo "=== v3 containerized benchmark ==="
echo ""

# Start postgres
echo "[1/5] Starting PostgreSQL..."
podman compose -f "$COMPOSE_FILE" up -d postgres 2>&1
echo "       Waiting for postgres healthy..."
for i in $(seq 1 30); do
  if podman exec bench-postgres pg_isready -U bench -d bench >/dev/null 2>&1; then
    echo "       PostgreSQL ready."
    break
  fi
  sleep 1
done

# Create schema if not exists
echo "       Creating schema..."
podman exec bench-postgres psql -U bench -d bench -c "
  CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );" >/dev/null 2>&1

# Seed users
echo "[2/5] Seeding $SEED_COUNT users..."
for i in $(seq 1 "$SEED_COUNT"); do
  podman exec bench-postgres psql -U bench -d bench -c \
    "INSERT INTO users (name, email) VALUES ('Seed User $i', 'seed$i@example.com') ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true
done
SEEDED_IDS=$(podman exec bench-postgres psql -U bench -d bench -t -A -c \
  "SELECT string_agg(id::text, ',') FROM (SELECT id FROM users ORDER BY created_at LIMIT $SEED_COUNT) t;")
echo "       Seeded $(echo "$SEEDED_IDS" | tr ',' '\n' | wc -l | tr -d ' ') users."

run_target() {
  local name="$1"
  local port
  port="$(get_port "$name")"
  local base_url="http://localhost:${port}"

  echo ""
  echo "  [4/5] Starting $name (port $port)..."
  podman compose -f "$COMPOSE_FILE" --profile "$name" up -d "$name" 2>&1

  echo "       Waiting for $name to be healthy..."
  for i in $(seq 1 30); do
    if curl -fsS "$base_url/health" >/dev/null 2>&1; then
      echo "       $name healthy."
      break
    fi
    sleep 1
  done

  if ! curl -fsS "$base_url/health" >/dev/null 2>&1; then
    echo "       ERROR: $name failed to start."
    podman compose -f "$COMPOSE_FILE" logs "$name" 2>&1 | tail -20
    FAILED_TARGETS+=("$name:start_failed")
    return 1
  fi

  # Verify startup config
  echo "       Verifying startup config..."
  podman compose -f "$COMPOSE_FILE" logs "$name" 2>&1 | grep -E "pool_min=.*pool_max=.*notify_log_enabled" || echo "       (config log check: manual verification recommended)"

  echo ""
  echo "  [5/5] Running v3 benchmark against $name..."
  echo "============================================================"

  cd "$PROJECT_ROOT"
  if ! BENCH_NOTIFY_LOG=false \
    BENCH_USER_IDS="$SEEDED_IDS" \
    bash bench/scripts/run-v2-all.sh \
    "$name" \
    "$base_url" \
    "$SEEDED_IDS" \
    bench/results \
    "v3-$(date +%Y%m%d-%H%M%S)-${name}"; then
    FAILED_TARGETS+=("$name:benchmark_failed")
    return 1
  fi

  echo ""
  echo "  Stopping $name..."
  podman stop "bench-$name" 2>&1 || true
  podman rm -f "bench-$name" 2>&1 || true
}

echo "[3/5] Building + benchmarking..."
if [ "$TARGET" = "all" ]; then
  for name in "${ALL_TARGETS[@]}"; do
    if ! run_target "$name"; then
      echo "  WARNING: $name failed; continuing full matrix run."
    fi
  done
elif [ "$TARGET" = "official" ]; then
  for name in "${OFFICIAL_TARGETS[@]}"; do
    if ! run_target "$name"; then
      echo "  ERROR: official lane $name failed; stopping."
      break
    fi
  done
else
  if [ -z "$(get_port "$TARGET")" ]; then
    echo "error: unknown target '$TARGET'. valid: rust-axum go-fiber go-nethttp-chi dotnet-jit dotnet-aot official all"
    podman compose -f "$COMPOSE_FILE" down 2>&1
    exit 1
  fi
  run_target "$TARGET"
fi

echo ""
echo "============================================================"
echo "  v3 containerized benchmark complete"
echo "  results: $OUTPUT_ROOT"
echo "============================================================"
if [ "${#FAILED_TARGETS[@]}" -gt 0 ]; then
  echo "Failed targets:"
  printf '  - %s\n' "${FAILED_TARGETS[@]}"
fi

# Leave postgres running for convenience; user can `podman compose down` manually
echo "PostgreSQL still running. Stop with: podman compose -f $COMPOSE_FILE down"
