#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <jit|aot> <publish-dir> <port> [database-url] [pid-file]"
  echo "example: $0 jit implementations/dotnet-minimal/microservice/out/jit/publish 3003"
  exit 1
fi

LANE="$1"
PUBLISH_DIR_RAW="$2"
PORT="$3"
DATABASE_URL="${4:-Host=localhost;Port=5433;Database=bench;Username=bench;Password=bench}"
PID_FILE_RAW="${5:-}"
USE_PODMAN_DOTNET="${USE_PODMAN_DOTNET:-false}"
DOTNET_CONTAINER_ENGINE="${DOTNET_CONTAINER_ENGINE:-podman}"
DOTNET_ASPNET_IMAGE="${DOTNET_ASPNET_IMAGE:-mcr.microsoft.com/dotnet/aspnet:10.0}"
DOTNET_RUNTIME_DEPS_IMAGE="${DOTNET_RUNTIME_DEPS_IMAGE:-mcr.microsoft.com/dotnet/runtime-deps:10.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

to_container_path() {
  local host_path="$1"
  if [[ "$host_path" == "$PROJECT_ROOT" ]]; then
    echo "/work"
    return
  fi
  if [[ "$host_path" == "$PROJECT_ROOT"/* ]]; then
    echo "/work/${host_path#$PROJECT_ROOT/}"
    return
  fi
  echo "$host_path"
}

TOOL_DATABASE_URL="$DATABASE_URL"
if [ "$USE_PODMAN_DOTNET" = "true" ]; then
  if [ "$DOTNET_CONTAINER_ENGINE" = "docker" ]; then
    TOOL_DATABASE_URL="${TOOL_DATABASE_URL/Host=localhost/Host=host.docker.internal}"
    TOOL_DATABASE_URL="${TOOL_DATABASE_URL/Host=127.0.0.1/Host=host.docker.internal}"
  else
    TOOL_DATABASE_URL="${TOOL_DATABASE_URL/Host=localhost/Host=host.containers.internal}"
    TOOL_DATABASE_URL="${TOOL_DATABASE_URL/Host=127.0.0.1/Host=host.containers.internal}"
  fi
fi

if [[ "$PUBLISH_DIR_RAW" = /* ]]; then
  PUBLISH_DIR="$PUBLISH_DIR_RAW"
else
  PUBLISH_DIR="$PROJECT_ROOT/$PUBLISH_DIR_RAW"
fi

if [ ! -d "$PUBLISH_DIR" ]; then
  echo "publish directory not found: $PUBLISH_DIR"
  exit 1
fi

if [[ -n "$PID_FILE_RAW" ]]; then
  if [[ "$PID_FILE_RAW" = /* ]]; then
    PID_FILE="$PID_FILE_RAW"
  else
    PID_FILE="$PROJECT_ROOT/$PID_FILE_RAW"
  fi
else
  PID_FILE=""
fi

start_jit() {
  local app_dll="$PUBLISH_DIR/microservice.dll"
  if [ ! -f "$app_dll" ]; then
    echo "jit app dll not found: $app_dll"
    exit 1
  fi

  if [ "$USE_PODMAN_DOTNET" = "true" ]; then
    if ! command -v "$DOTNET_CONTAINER_ENGINE" >/dev/null 2>&1; then
      echo "missing required command: $DOTNET_CONTAINER_ENGINE"
      exit 1
    fi
    local publish_container container_name
    publish_container="$(to_container_path "$PUBLISH_DIR")"
    container_name="bench-dotnet-jit-$PORT-$(date +%s)"
    "$DOTNET_CONTAINER_ENGINE" run -d --rm \
      --name "$container_name" \
      -p "$PORT:$PORT" \
      -v "$PROJECT_ROOT:/work" \
      -w /work \
      -e BENCH_NOTIFY_LOG=false \
      -e PORT="$PORT" \
      -e DATABASE_URL="$TOOL_DATABASE_URL" \
      "$DOTNET_ASPNET_IMAGE" \
      dotnet "$publish_container/microservice.dll" >/dev/null
    echo "$container_name"
  else
    if ! command -v dotnet >/dev/null 2>&1; then
      echo "missing required command: dotnet"
      exit 1
    fi
    BENCH_NOTIFY_LOG=false PORT="$PORT" DATABASE_URL="$TOOL_DATABASE_URL" \
      dotnet "$app_dll" >/dev/null 2>&1 &
    echo $!
  fi
}

start_aot() {
  local bin
  bin="$(python3 - "$PUBLISH_DIR" <<'PY'
import os
import sys

root = sys.argv[1]
candidates = []
for name in os.listdir(root):
    p = os.path.join(root, name)
    if os.path.isfile(p) and os.access(p, os.X_OK) and not name.endswith('.dll'):
        candidates.append(name)

for preferred in ("microservice", "microservice.exe"):
    if preferred in candidates:
        print(os.path.join(root, preferred))
        sys.exit(0)

if candidates:
    print(os.path.join(root, sorted(candidates)[0]))
    sys.exit(0)

sys.exit(1)
PY
)"

  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    echo "aot executable not found in: $PUBLISH_DIR"
    exit 1
  fi

  if [ "$USE_PODMAN_DOTNET" = "true" ]; then
    if ! command -v "$DOTNET_CONTAINER_ENGINE" >/dev/null 2>&1; then
      echo "missing required command: $DOTNET_CONTAINER_ENGINE"
      exit 1
    fi
    local publish_container bin_container container_name
    publish_container="$(to_container_path "$PUBLISH_DIR")"
    bin_container="$(to_container_path "$bin")"
    container_name="bench-dotnet-aot-$PORT-$(date +%s)"
    "$DOTNET_CONTAINER_ENGINE" run -d --rm \
      --name "$container_name" \
      -p "$PORT:$PORT" \
      -v "$PROJECT_ROOT:/work" \
      -w /work \
      -e BENCH_NOTIFY_LOG=false \
      -e PORT="$PORT" \
      -e DATABASE_URL="$TOOL_DATABASE_URL" \
      "$DOTNET_RUNTIME_DEPS_IMAGE" \
      "$bin_container" >/dev/null
    echo "$container_name"
  else
    BENCH_NOTIFY_LOG=false PORT="$PORT" DATABASE_URL="$TOOL_DATABASE_URL" \
      "$bin" >/dev/null 2>&1 &
    echo $!
  fi
}

case "$LANE" in
  jit)
    pid="$(start_jit)"
    ;;
  aot)
    pid="$(start_aot)"
    ;;
  *)
    echo "invalid lane: $LANE"
    echo "expected one of: jit, aot"
    exit 1
    ;;
esac

if [ -n "$PID_FILE" ]; then
  mkdir -p "$(dirname "$PID_FILE")"
  printf '%s\n' "$pid" > "$PID_FILE"
fi

echo "$pid"
