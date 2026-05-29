#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <jit|aot> [publish-root]"
  echo "example: $0 jit"
  exit 1
fi

LANE="$1"
PUBLISH_ROOT="${2:-implementations/dotnet-minimal/microservice/out}"
USE_PODMAN_DOTNET="${USE_PODMAN_DOTNET:-false}"
DOTNET_CONTAINER_ENGINE="${DOTNET_CONTAINER_ENGINE:-podman}"
DOTNET_SDK_IMAGE="${DOTNET_SDK_IMAGE:-mcr.microsoft.com/dotnet/sdk:10.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JIT_SERVICE_DIR="$PROJECT_ROOT/implementations/dotnet-minimal/microservice"
AOT_SERVICE_DIR="$PROJECT_ROOT/implementations/dotnet-aot/microservice"

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

run_publish() {
  local lane_kind="$1"
  local service_dir="$2"
  local out_dir="$3"
  shift 3

  mkdir -p "$out_dir"

  if [ "$USE_PODMAN_DOTNET" = "true" ]; then
    if ! command -v "$DOTNET_CONTAINER_ENGINE" >/dev/null 2>&1; then
      echo "missing required command: $DOTNET_CONTAINER_ENGINE"
      exit 1
    fi

    local service_container out_container
    service_container="$(to_container_path "$service_dir")"
    out_container="$(to_container_path "$out_dir")"

    if [ "$lane_kind" = "aot" ]; then
      local publish_cmd
      publish_cmd="dotnet publish $service_container"
      for arg in "$@"; do
        publish_cmd+=" $(printf '%q' "$arg")"
      done
      publish_cmd+=" -o $out_container"

      "$DOTNET_CONTAINER_ENGINE" run --rm -i \
        --platform linux/arm64 \
        -v "$PROJECT_ROOT:/work" \
        -w /work \
        -e DOTNET_CLI_HOME=/tmp \
        -e DOTNET_EnableHWIntrinsic=0 \
        -e COMPlus_EnableHWIntrinsic=0 \
        "$DOTNET_SDK_IMAGE" \
        /bin/sh -lc "command -v clang >/dev/null 2>&1 || (apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends clang zlib1g-dev >/dev/null); $publish_cmd" >/dev/null
    else
      "$DOTNET_CONTAINER_ENGINE" run --rm -i \
        --platform linux/arm64 \
        -v "$PROJECT_ROOT:/work" \
        -w /work \
        -e DOTNET_CLI_HOME=/tmp \
        -e DOTNET_EnableHWIntrinsic=0 \
        -e COMPlus_EnableHWIntrinsic=0 \
        "$DOTNET_SDK_IMAGE" \
        dotnet publish "$service_container" "$@" -o "$out_container" >/dev/null
    fi
  else
    if ! command -v dotnet >/dev/null 2>&1; then
      echo "missing required command: dotnet"
      exit 1
    fi
    if [ "$lane_kind" = "aot" ] && [ "$(uname -s)" = "Darwin" ]; then
      local lib_path_parts=()
      if [ -d "/opt/homebrew/opt/openssl@3/lib" ]; then
        lib_path_parts+=("/opt/homebrew/opt/openssl@3/lib")
      fi
      if [ -d "/opt/homebrew/opt/brotli/lib" ]; then
        lib_path_parts+=("/opt/homebrew/opt/brotli/lib")
      fi
      if [ -n "${LIBRARY_PATH:-}" ]; then
        lib_path_parts+=("${LIBRARY_PATH}")
      fi

      local merged_library_path=""
      if [ "${#lib_path_parts[@]}" -gt 0 ]; then
        merged_library_path="$(IFS=:; echo "${lib_path_parts[*]}")"
      fi

      if [ -n "$merged_library_path" ]; then
        LIBRARY_PATH="$merged_library_path" dotnet publish "$service_dir" "$@" -o "$out_dir" >/dev/null
      else
        dotnet publish "$service_dir" "$@" -o "$out_dir" >/dev/null
      fi
    else
      dotnet publish "$service_dir" "$@" -o "$out_dir" >/dev/null
    fi
  fi
}

if [[ "$PUBLISH_ROOT" = /* ]]; then
  RESOLVED_PUBLISH_ROOT="$PUBLISH_ROOT"
else
  RESOLVED_PUBLISH_ROOT="$PROJECT_ROOT/$PUBLISH_ROOT"
fi

case "$LANE" in
  jit)
    OUT_DIR="$RESOLVED_PUBLISH_ROOT/jit/publish"
    run_publish "jit" "$JIT_SERVICE_DIR" "$OUT_DIR" -c Release
    ;;
  aot)
    OUT_DIR="$RESOLVED_PUBLISH_ROOT/aot/publish"
    if [ -n "${DOTNET_AOT_RID:-}" ]; then
      DOTNET_AOT_RID="$DOTNET_AOT_RID"
    elif [ "$USE_PODMAN_DOTNET" = "true" ]; then
      arch="$(uname -m)"
      case "$arch" in
        arm64|aarch64)
          DOTNET_AOT_RID="linux-arm64"
          ;;
        x86_64|amd64)
          DOTNET_AOT_RID="linux-x64"
          ;;
        *)
          echo "unsupported architecture for default DOTNET_AOT_RID: $arch"
          echo "set DOTNET_AOT_RID explicitly"
          exit 1
          ;;
      esac
    else
      DOTNET_AOT_RID="osx-arm64"
    fi
    run_publish "aot" "$AOT_SERVICE_DIR" "$OUT_DIR" -c Release -r "$DOTNET_AOT_RID" -p:PublishAot=true -p:StripSymbols=true
    ;;
  *)
    echo "invalid lane: $LANE"
    echo "expected one of: jit, aot"
    exit 1
    ;;
esac

echo "$OUT_DIR"
