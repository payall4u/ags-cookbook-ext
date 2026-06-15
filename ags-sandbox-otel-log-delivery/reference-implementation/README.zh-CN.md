# 参考实现

`images/sandbox` 是一个可运行的参考实现，用来演示如何在 AGS custom image 中启动客户业务进程、envd 控制通道和 OpenTelemetry Collector。

在端到端验证时，可以先构建并推送这个目录下的示例镜像，用它确认 VPC、envd 注入、collector 和客户日志入口都已连通。正式接入客户业务时，再替换 `app/` 和 `pyproject.toml`，保留 `entrypoint.sh` 中的 InstanceID 注入和 collector 启动逻辑。

它包含：

- `Dockerfile`：安装 Python、`uv`、业务依赖，并复制 AGS `envd` 和 `otelcol-contrib`。
- `entrypoint.sh`：启动 envd 和业务命令，等待控制面注入本次 `InstanceID`，注入成功后再启动 collector。
- `app/server.py`：用于验证的 FastAPI 服务，会将 heartbeat、health check 和请求日志写入 `/app/logs/app.log`。

替换业务代码后，同时在 `.env.local` 中更新 `BUSINESS_COMMAND`、`SERVICE_NAME`、`LOG_FILE_PATTERNS` 和 `EXTRA_ENV_JSON`。

业务日志目录通过 `LOG_FILE_PATTERNS` 指定，环境变量属性通过 `LOG_RESOURCE_ENV_KEYS` allowlist 指定，wrapper 不修改业务日志内容和格式。
