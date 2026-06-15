#!/usr/bin/env bash
set -Eeuo pipefail

COLLECTOR_LOG_FILE="${COLLECTOR_LOG_FILE:-/var/log/ags-collector/otelcol.log}"
ENVD_COMMAND="${ENVD_COMMAND:-/usr/bin/envd}"
ENVD_ARGS="${ENVD_ARGS:--port 49983}"
LOG_EXCLUDE_FILE_PATTERNS="${LOG_EXCLUDE_FILE_PATTERNS:-/var/log/ags-collector/*.log}"
LOG_FILE_PATTERNS="${LOG_FILE_PATTERNS:-/app/logs/*.log}"
LOG_RESOURCE_ENV_KEYS="${LOG_RESOURCE_ENV_KEYS:-}"
LOG_START_AT="${LOG_START_AT:-beginning}"
OTELCOL_COMMAND="${OTELCOL_COMMAND:-/usr/local/bin/otelcol-contrib}"
OTEL_CONFIG_FILE="${OTEL_CONFIG_FILE:-/etc/otelcol/config.yaml}"
OTEL_EXPORTER_OTLP_INSECURE="${OTEL_EXPORTER_OTLP_INSECURE:-true}"
SANDBOX_ID_PIPE="${SANDBOX_ID_PIPE:-/run/ags/sandbox-id.pipe}"
SANDBOX_ID_WAIT_TIMEOUT="${SANDBOX_ID_WAIT_TIMEOUT:-0}"
SERVICE_NAME="${SERVICE_NAME:-ags-log-delivery-demo}"

mkdir -p "$(dirname "$COLLECTOR_LOG_FILE")" "$(dirname "$SANDBOX_ID_PIPE")" "$(dirname "$OTEL_CONFIG_FILE")"
touch "$COLLECTOR_LOG_FILE"

app_pid=""
collector_pid=""
envd_pid=""
identity_waiter_pid=""

log_entrypoint() {
  printf '%s %s\n' "$(date -Iseconds)" "$*" >&2
}

yaml_quote() {
  local value="${1//\\/\\\\}"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

append_yaml_list() {
  local csv="$1"
  local item

  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [[ -n "$item" ]]; then
      printf '      - %s\n' "$(yaml_quote "$item")"
    fi
  done
}

append_resource_attributes() {
  local sandbox_id="$1"
  local env_key
  local attr_key
  local attr_value

  cat <<EOF
      - key: service.name
        value: $(yaml_quote "$SERVICE_NAME")
        action: upsert
      - key: service.instance.id
        value: $(yaml_quote "$sandbox_id")
        action: upsert
      - key: ags.sandbox.id
        value: $(yaml_quote "$sandbox_id")
        action: upsert
      - key: deployment.environment.name
        value: $(yaml_quote "${DEPLOYMENT_ENVIRONMENT:-ags-sandbox}")
        action: upsert
EOF

  IFS=',' read -ra env_keys <<< "$LOG_RESOURCE_ENV_KEYS"
  for env_key in "${env_keys[@]}"; do
    env_key="${env_key#"${env_key%%[![:space:]]*}"}"
    env_key="${env_key%"${env_key##*[![:space:]]}"}"
    if [[ -z "$env_key" || ! "$env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      continue
    fi
    if [[ -z "${!env_key+x}" ]]; then
      continue
    fi
    attr_key="$(printf '%s' "$env_key" | tr '[:upper:]' '[:lower:]')"
    attr_value="${!env_key}"
    cat <<EOF
      - key: env.${attr_key}
        value: $(yaml_quote "$attr_value")
        action: upsert
EOF
  done
}

render_otel_config() {
  local sandbox_id="$1"

  {
    cat <<EOF
receivers:
  file_log:
    include:
EOF
    append_yaml_list "$LOG_FILE_PATTERNS"
    cat <<EOF
    exclude:
EOF
    append_yaml_list "$LOG_EXCLUDE_FILE_PATTERNS"
    cat <<EOF
    start_at: ${LOG_START_AT}
    include_file_path: true
    include_file_name: true

processors:
  batch: {}
  resource:
    attributes:
EOF
    append_resource_attributes "$sandbox_id"
    cat <<EOF

exporters:
  otlp_grpc:
    endpoint: $(yaml_quote "${OTEL_EXPORTER_OTLP_ENDPOINT}")
    tls:
      insecure: ${OTEL_EXPORTER_OTLP_INSECURE}

service:
  pipelines:
    logs:
      receivers: [file_log]
      processors: [resource, batch]
      exporters: [otlp_grpc]
EOF
  } > "$OTEL_CONFIG_FILE"
}

prepare_identity_pipe() {
  rm -f "$SANDBOX_ID_PIPE"
  mkfifo "$SANDBOX_ID_PIPE"
}

read_sandbox_id() {
  exec 3<>"$SANDBOX_ID_PIPE"
  if [[ "$SANDBOX_ID_WAIT_TIMEOUT" == "0" ]]; then
    IFS= read -r sandbox_id <&3
  else
    IFS= read -r -t "$SANDBOX_ID_WAIT_TIMEOUT" sandbox_id <&3 || {
      exec 3>&-
      return 1
    }
  fi
  exec 3>&-

  [[ -n "${sandbox_id:-}" ]]
}

start_envd() {
  local envd_path=""

  if [[ -x "$ENVD_COMMAND" ]]; then
    envd_path="$ENVD_COMMAND"
  elif command -v "$ENVD_COMMAND" >/dev/null 2>&1; then
    envd_path="$(command -v "$ENVD_COMMAND")"
  fi

  if [[ -z "$envd_path" ]]; then
    log_entrypoint "envd command not found; AGS exec injection will be unavailable: $ENVD_COMMAND"
    return 0
  fi

  # shellcheck disable=SC2086
  "$envd_path" $ENVD_ARGS >>"$COLLECTOR_LOG_FILE" 2>&1 &
  envd_pid="$!"
  log_entrypoint "started envd pid=$envd_pid"
}

start_collector_after_identity() {
  local sandbox_id=""

  if [[ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]]; then
    log_entrypoint "OTEL_EXPORTER_OTLP_ENDPOINT is not set; log collector is disabled"
    return 0
  fi

  prepare_identity_pipe
  log_entrypoint "waiting for sandbox id injection on $SANDBOX_ID_PIPE"
  if ! read_sandbox_id; then
    log_entrypoint "sandbox id was not injected; collector will not start"
    return 0
  fi

  render_otel_config "$sandbox_id"
  "$OTELCOL_COMMAND" --config "$OTEL_CONFIG_FILE" >>"$COLLECTOR_LOG_FILE" 2>&1 &
  collector_pid="$!"
  log_entrypoint "started OpenTelemetry Collector pid=$collector_pid sandbox_id=$sandbox_id"

  sleep 2
  if ! kill -0 "$collector_pid" >/dev/null 2>&1; then
    log_entrypoint "OpenTelemetry Collector exited during startup; see $COLLECTOR_LOG_FILE"
  fi
}

stop_children() {
  local status=$?
  trap - EXIT INT TERM

  for pid in "$app_pid" "$collector_pid" "$identity_waiter_pid" "$envd_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done

  exit "$status"
}

trap stop_children EXIT INT TERM

start_envd
start_collector_after_identity &
identity_waiter_pid="$!"

log_entrypoint "starting application: $*"
set +e
"$@" &
app_pid="$!"
wait "$app_pid"
app_status="$?"
set -e
exit "$app_status"
