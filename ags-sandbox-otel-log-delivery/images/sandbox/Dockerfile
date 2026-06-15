FROM ccr.ccs.tencentyun.com/ags-image/envd:latest AS envd
FROM otel/opentelemetry-collector-contrib:0.151.0 AS otelcol

FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:/root/.local/bin:${PATH}" \
    APP_PORT=8080 \
    ENVD_COMMAND=/usr/bin/envd \
    ENVD_ARGS="-port 49983" \
    LOG_FILE_PATTERNS="/app/logs/*.log"

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir uv

WORKDIR /app

COPY --from=envd /usr/bin/envd /usr/bin/envd
COPY --from=otelcol /otelcol-contrib /usr/local/bin/otelcol-contrib
COPY pyproject.toml ./
RUN uv sync --no-dev

COPY app ./app
COPY entrypoint.sh /opt/ags/entrypoint.sh
RUN chmod +x /opt/ags/entrypoint.sh /usr/bin/envd \
    && mkdir -p /app/logs /run/ags /var/log/ags-collector /etc/otelcol

EXPOSE 8080
EXPOSE 49983

CMD ["/opt/ags/entrypoint.sh", "bash", "-lc", "uv run uvicorn app.server:app --host 0.0.0.0 --port ${APP_PORT}"]
