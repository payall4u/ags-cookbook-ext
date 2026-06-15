#!/usr/bin/env bash
set -Eeuo pipefail

: "${QUERY:={service_name=\"ags-log-delivery-demo\"}}"
: "${LIMIT:=20}"

docker exec otel-lgtm curl -G -fsS \
  http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode "query=$QUERY" \
  --data-urlencode "limit=$LIMIT"
