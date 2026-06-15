#!/usr/bin/env bash
set -Eeuo pipefail

: "${REMOTE_BUILD_HOST:?set REMOTE_BUILD_HOST, for example root@<build-host>}"
: "${REMOTE_BUILD_PORT:=22}"
: "${IMAGE:?set IMAGE, for example ccr.ccs.tencentyun.com/<namespace>/<repo>:<tag>}"

archive="/tmp/ags-log-sandbox-build.tar.gz"
remote_dir="/tmp/ags-log-sandbox-build"

tar -czf "$archive" -C images/sandbox .
scp -P "$REMOTE_BUILD_PORT" "$archive" "$REMOTE_BUILD_HOST:$archive"
ssh -p "$REMOTE_BUILD_PORT" "$REMOTE_BUILD_HOST" \
  "rm -rf '$remote_dir' && mkdir -p '$remote_dir' && tar -xzf '$archive' -C '$remote_dir' && cd '$remote_dir' && docker build -t '$IMAGE' . && docker push '$IMAGE'"
