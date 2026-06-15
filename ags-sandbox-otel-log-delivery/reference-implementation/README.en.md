# Reference Implementation

`images/sandbox` is a runnable reference implementation that shows how to start the customer application process, the envd control channel, and OpenTelemetry Collector inside an AGS custom image.

For end-to-end validation, you can build and push this example image first to confirm VPC connectivity, envd injection, collector startup, and the customer log ingress. When adapting this image for a customer application, replace `app/` and `pyproject.toml` while keeping the InstanceID injection and collector startup logic in `entrypoint.sh`.

It contains:

- `Dockerfile`: installs Python, `uv`, application dependencies, and copies AGS `envd` plus `otelcol-contrib`.
- `entrypoint.sh`: starts envd and the application command, waits for the control plane to inject the current `InstanceID`, and starts the collector only after successful injection.
- `app/server.py`: a validation FastAPI service that writes heartbeat, health-check, and request logs to `/app/logs/app.log`.

After replacing the application code, also update `BUSINESS_COMMAND`, `SERVICE_NAME`, `LOG_FILE_PATTERNS`, and `EXTRA_ENV_JSON` in `.env.local`.

Application log paths are configured through `LOG_FILE_PATTERNS`, and environment attributes are allowlisted through `LOG_RESOURCE_ENV_KEYS`; the wrapper does not modify log content or format.
