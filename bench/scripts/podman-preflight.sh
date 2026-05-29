#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <base-url> [wrk-image] [k6-image]"
  echo "example: $0 http://localhost:3001"
  exit 1
fi

BASE_URL_RAW="$1"
WRK_IMAGE="${2:-${PODMAN_WRK_IMAGE:-docker.io/williamyeh/wrk}}"
K6_IMAGE="${3:-${PODMAN_K6_IMAGE:-docker.io/grafana/k6:latest}}"
WRK_CONTAINERFILE="${PODMAN_WRK_CONTAINERFILE:-bench/podman/wrk/Containerfile}"
WRK_LOCAL_IMAGE="${PODMAN_WRK_LOCAL_IMAGE:-local/bench-wrk:arm64}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman not found on PATH"
  exit 1
fi

HOST_URL="$BASE_URL_RAW"
TOOL_URL="${BASE_URL_RAW/localhost/host.containers.internal}"
TOOL_URL="${TOOL_URL/127.0.0.1/host.containers.internal}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "$WRK_IMAGE" = "auto" ]; then
  if [[ "$WRK_CONTAINERFILE" = /* ]]; then
    WRK_CONTAINERFILE_PATH="$WRK_CONTAINERFILE"
  else
    WRK_CONTAINERFILE_PATH="$PROJECT_ROOT/$WRK_CONTAINERFILE"
  fi

  if [ ! -f "$WRK_CONTAINERFILE_PATH" ]; then
    echo "wrk containerfile not found: $WRK_CONTAINERFILE_PATH"
    exit 1
  fi

  echo "[preflight] building local arm64 wrk image: $WRK_LOCAL_IMAGE"
  podman build --platform linux/arm64 -t "$WRK_LOCAL_IMAGE" -f "$WRK_CONTAINERFILE_PATH" "$PROJECT_ROOT" >/dev/null
  WRK_IMAGE="$WRK_LOCAL_IMAGE"
fi

echo "[preflight] host-url: $HOST_URL"
echo "[preflight] tool-url: $TOOL_URL"
echo "[preflight] wrk-image: $WRK_IMAGE"
echo "[preflight] k6-image: $K6_IMAGE"

echo "[preflight] pulling podman images"
if [[ "$WRK_IMAGE" == local/* ]] || [[ "$WRK_IMAGE" == localhost/* ]]; then
  echo "[preflight] skipping pull for local wrk image: $WRK_IMAGE"
else
  podman pull "$WRK_IMAGE" >/dev/null
fi
podman pull "$K6_IMAGE" >/dev/null

echo "[preflight] checking host /health from host shell"
if ! curl -fsS "$HOST_URL/health" >/dev/null; then
  echo "host cannot reach $HOST_URL/health"
  exit 1
fi

echo "[preflight] checking host.containers.internal DNS from container"
if ! podman run --rm --platform linux/arm64 --entrypoint /bin/sh "$WRK_IMAGE" -c "getent hosts host.containers.internal >/dev/null 2>&1 || ping -c 1 host.containers.internal >/dev/null 2>&1"; then
  echo "container cannot resolve host.containers.internal"
  exit 1
fi

echo "[preflight] checking /health from container"
if ! podman run --rm --platform linux/arm64 --entrypoint /bin/sh "$WRK_IMAGE" -c "command -v curl >/dev/null 2>&1 && curl -fsS '$TOOL_URL/health' >/dev/null"; then
  echo "wrk image cannot probe health directly (curl missing or request failed)"
  echo "this is non-fatal for wrk itself, continuing with a wrk smoke check"
fi

echo "[preflight] running wrk smoke check"
if ! podman run --rm --platform linux/arm64 "$WRK_IMAGE" -c 2 -d 2s -t 1 "$TOOL_URL/health" >/dev/null; then
  echo "wrk smoke check failed against $TOOL_URL/health"
  exit 1
fi

echo "[preflight] running k6 smoke check"
if ! podman run --rm --platform linux/arm64 --entrypoint /bin/sh -e BASE_URL="$TOOL_URL" "$K6_IMAGE" -lc "cat <<'EOF' >/tmp/smoke.js
import http from 'k6/http';
import { check } from 'k6';

export const options = { vus: 1, iterations: 1 };

export default function () {
  const base = __ENV.BASE_URL || 'http://host.containers.internal:3001';
  const res = http.get(base + '/health');
  check(res, { 'status is 200': (r) => r.status === 200 });
}
EOF
k6 run -q /tmp/smoke.js" >/dev/null
then
  echo "k6 smoke check failed against $TOOL_URL/health"
  exit 1
fi

echo "[preflight] success"
