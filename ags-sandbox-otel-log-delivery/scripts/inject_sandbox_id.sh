#!/usr/bin/env bash
set -Eeuo pipefail

: "${INSTANCE_ID:?set INSTANCE_ID}"
: "${SANDBOX_ID:=$INSTANCE_ID}"
: "${SANDBOX_ID_PIPE:=/run/ags/sandbox-id.pipe}"
: "${INJECT_METHOD:=sdk}"

payload="$(printf '%s' "$SANDBOX_ID" | base64 | tr -d '\n')"
pipe_path="$(printf '%s' "$SANDBOX_ID_PIPE" | sed "s/'/'\\\\''/g")"
remote_command="printf '%s\n' \"\$(printf '%s' '$payload' | base64 -d)\" > '$pipe_path'"

if [[ "$INJECT_METHOD" == "agr" ]]; then
  "${AGR_BIN:-agr}" instance exec "$INSTANCE_ID" -o json -- sh -lc "$remote_command"
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
(
  cd "$script_dir/ags-envd-exec"
  COMMAND="$remote_command" go run .
)
