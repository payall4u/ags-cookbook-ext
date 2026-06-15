#!/usr/bin/env bash
set -Eeuo pipefail

: "${AGS_IMAGE:?set AGS_IMAGE}"
: "${AGS_TOOL_NAME:?set AGS_TOOL_NAME}"
: "${AGS_IMAGE_REGISTRY_TYPE:=personal}"
: "${AGS_ROLE_ARN:=}"
: "${AGS_SUBNET_ID:?set AGS_SUBNET_ID}"
: "${AGS_SECURITY_GROUP_ID:?set AGS_SECURITY_GROUP_ID}"
: "${OTLP_ENDPOINT:?set OTLP_ENDPOINT, for example <collector-private-host>:4317}"
: "${SERVICE_NAME:=ags-log-delivery-demo}"
: "${APP_PORT:=8080}"
: "${BUSINESS_COMMAND:=uv run uvicorn app.server:app --host 0.0.0.0 --port ${APP_PORT}}"
: "${OTEL_EXPORTER_OTLP_INSECURE:=true}"
: "${LOG_FILE_PATTERNS:=/app/logs/*.log}"
: "${LOG_EXCLUDE_FILE_PATTERNS:=/var/log/ags-collector/*.log}"
: "${LOG_RESOURCE_ENV_KEYS:=}"
: "${LOG_START_AT:=beginning}"
: "${SANDBOX_ID_PIPE:=/run/ags/sandbox-id.pipe}"
: "${SANDBOX_ID_WAIT_TIMEOUT:=0}"
: "${ENVD_COMMAND:=/usr/bin/envd}"
: "${ENVD_ARGS:=-port 49983}"
: "${ENVD_PORT:=49983}"
: "${PROBE_PATH:=/health}"
: "${PROBE_PORT:=$ENVD_PORT}"
: "${PROBE_READY_TIMEOUT_MS:=30000}"
: "${PROBE_TIMEOUT_MS:=1000}"
: "${PROBE_PERIOD_MS:=3000}"
: "${PROBE_FAILURE_THRESHOLD:=10}"
: "${EXTRA_ENV_JSON:=[]}"
: "${AGS_RESOURCE_CPU:=2}"
: "${AGS_RESOURCE_MEMORY:=4Gi}"
: "${AGS_DEFAULT_TIMEOUT:=1h}"
: "${AGS_TOOL_DESCRIPTION:=AGS sandbox service that delivers application logs to a customer-owned OTLP/gRPC collector}"
: "${PURPOSE_TAG:=ags-log-delivery}"
: "${PROJECT_TAG:=}"
: "${OWNER_TAG:=}"
: "${BILLING_TAG_VALUE:=}"

request_file="$(mktemp)"
trap 'rm -f "$request_file"' EXIT

jq -n \
  --arg tool_name "$AGS_TOOL_NAME" \
  --arg image "$AGS_IMAGE" \
  --arg registry_type "$AGS_IMAGE_REGISTRY_TYPE" \
  --arg role_arn "$AGS_ROLE_ARN" \
  --arg subnet_id "$AGS_SUBNET_ID" \
  --arg sg_id "$AGS_SECURITY_GROUP_ID" \
  --arg otlp_endpoint "$OTLP_ENDPOINT" \
  --arg otlp_insecure "$OTEL_EXPORTER_OTLP_INSECURE" \
  --arg service_name "$SERVICE_NAME" \
  --arg app_port "$APP_PORT" \
  --arg business_command "$BUSINESS_COMMAND" \
  --arg log_file_patterns "$LOG_FILE_PATTERNS" \
  --arg log_exclude_file_patterns "$LOG_EXCLUDE_FILE_PATTERNS" \
  --arg log_resource_env_keys "$LOG_RESOURCE_ENV_KEYS" \
  --arg log_start_at "$LOG_START_AT" \
  --arg sandbox_id_pipe "$SANDBOX_ID_PIPE" \
  --arg sandbox_id_wait_timeout "$SANDBOX_ID_WAIT_TIMEOUT" \
  --arg envd_command "$ENVD_COMMAND" \
  --arg envd_args "$ENVD_ARGS" \
  --arg envd_port "$ENVD_PORT" \
  --arg probe_path "$PROBE_PATH" \
  --arg probe_port "$PROBE_PORT" \
  --arg probe_ready_timeout_ms "$PROBE_READY_TIMEOUT_MS" \
  --arg probe_timeout_ms "$PROBE_TIMEOUT_MS" \
  --arg probe_period_ms "$PROBE_PERIOD_MS" \
  --arg probe_failure_threshold "$PROBE_FAILURE_THRESHOLD" \
  --argjson extra_env "$EXTRA_ENV_JSON" \
  --arg resource_cpu "$AGS_RESOURCE_CPU" \
  --arg resource_memory "$AGS_RESOURCE_MEMORY" \
  --arg default_timeout "$AGS_DEFAULT_TIMEOUT" \
  --arg description "$AGS_TOOL_DESCRIPTION" \
  --arg purpose_tag "$PURPOSE_TAG" \
  --arg project_tag "$PROJECT_TAG" \
  --arg owner_tag "$OWNER_TAG" \
  --arg billing_tag_value "$BILLING_TAG_VALUE" \
  '{
    ToolName: $tool_name,
    ToolType: "custom",
    Description: $description,
    DefaultTimeout: $default_timeout,
    NetworkConfiguration: {
      NetworkMode: "VPC",
      VpcConfig: {
        SubnetIds: [$subnet_id],
        SecurityGroupIds: [$sg_id]
      }
    },
    CustomConfiguration: {
      Image: $image,
      ImageRegistryType: $registry_type,
      Command: ["/opt/ags/entrypoint.sh"],
      Args: ["bash", "-lc", $business_command],
      Env: ([
        {Name: "OTEL_EXPORTER_OTLP_ENDPOINT", Value: $otlp_endpoint},
        {Name: "OTEL_EXPORTER_OTLP_INSECURE", Value: $otlp_insecure},
        {Name: "SERVICE_NAME", Value: $service_name},
        {Name: "APP_PORT", Value: $app_port},
        {Name: "LOG_FILE_PATTERNS", Value: $log_file_patterns},
        {Name: "LOG_EXCLUDE_FILE_PATTERNS", Value: $log_exclude_file_patterns},
        {Name: "LOG_RESOURCE_ENV_KEYS", Value: $log_resource_env_keys},
        {Name: "LOG_START_AT", Value: $log_start_at},
        {Name: "SANDBOX_ID_PIPE", Value: $sandbox_id_pipe},
        {Name: "SANDBOX_ID_WAIT_TIMEOUT", Value: $sandbox_id_wait_timeout},
        {Name: "ENVD_COMMAND", Value: $envd_command},
        {Name: "ENVD_ARGS", Value: $envd_args}
      ] + $extra_env),
      Ports: [
        {Name: "envd", Port: ($envd_port | tonumber), Protocol: "TCP"},
        {Name: "http", Port: ($app_port | tonumber), Protocol: "TCP"}
      ],
      Probe: {
        HttpGet: {Path: $probe_path, Port: ($probe_port | tonumber), Scheme: "HTTP"},
        ReadyTimeoutMs: ($probe_ready_timeout_ms | tonumber),
        ProbePeriodMs: ($probe_period_ms | tonumber),
        ProbeTimeoutMs: ($probe_timeout_ms | tonumber),
        SuccessThreshold: 1,
        FailureThreshold: ($probe_failure_threshold | tonumber)
      },
      Resources: {CPU: $resource_cpu, Memory: $resource_memory}
    }
  }
  | if $role_arn != "" then . + {RoleArn: $role_arn} else . end
  | (
      (if $purpose_tag != "" then [{Key: "purpose", Value: $purpose_tag}] else [] end)
      + (if $project_tag != "" then [{Key: "project", Value: $project_tag}] else [] end)
      + (if $owner_tag != "" then [{Key: "owner", Value: $owner_tag}] else [] end)
      + (if $billing_tag_value != "" then [{Key: "billing", Value: $billing_tag_value}] else [] end)
    ) as $tags
  | if ($tags | length) > 0 then . + {Tags: $tags} else . end' > "$request_file"

if [[ "${DRY_RUN:-false}" == "true" || "${DRY_RUN:-}" == "1" ]]; then
  cat "$request_file"
  exit 0
fi

"${AGR_BIN:-agr}" tool create --request "@$request_file" -o json
