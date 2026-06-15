# AGS 沙箱日志投递 Cookbook

本目录提供一套面向客户交付的 cookbook 和参考实现，用于将 AGS 沙箱内的业务文件日志，通过 VPC 网络投递到客户自建的 OpenTelemetry 兼容日志系统。

English README: [README.md](README.md)

## Cookbook 文档

- 中文：[cookbook.zh-CN.md](cookbook.zh-CN.md)
- 英文：[cookbook.en.md](cookbook.en.md)

## 支撑材料

- [iac/ags-tool.template.json](iac/ags-tool.template.json)：用于评审请求结构的 AGS custom Tool shape-only 模板。
- [iac/variables.example.env](iac/variables.example.env)：创建 Tool 所需变量示例。
- [scripts/inject_sandbox_id.sh](scripts/inject_sandbox_id.sh)：通过 AGS Go SDK envd command API 将当前 AGS InstanceID 写入沙箱。
- [scripts/ags-envd-exec](scripts/ags-envd-exec)：注入脚本使用的 Go SDK helper。
- [reference-implementation/README.zh-CN.md](reference-implementation/README.zh-CN.md)：中文参考镜像实现说明。
- [reference-implementation/README.en.md](reference-implementation/README.en.md)：英文参考镜像实现说明。
- [images/sandbox](images/sandbox)：可运行的沙箱镜像参考实现。

## 推荐执行顺序

1. 阅读中文或英文 cookbook，确认方案边界和运行流程。
2. 查看 `images/sandbox` 下的参考实现，理解镜像中如何集成 envd、wrapper 和 OpenTelemetry Collector。
3. 确认 AGS Tool 使用的 VPC 子网可以访问客户侧 OTLP/gRPC endpoint。
4. 构建并推送沙箱镜像，必要时在 AGS 中做镜像预热。
5. 复制并编辑 `.env.local`，生成 Tool 请求并创建 AGS Tool。
6. 启动实例，注入本次 `InstanceID`，然后在客户日志系统中验证日志和属性。

## 快速生成 Tool 请求

执行命令前先确认 cookbook 的方案边界：本方案只采集文件日志，且只有在 `InstanceID` 注入成功后才启动 collector。

```bash
# 先构建并推送沙箱镜像，再把镜像地址写入 AGS_IMAGE。
cp iac/variables.example.env .env.local
# source 前先编辑 .env.local。至少需要填写 AGS_IMAGE、
# AGS_SUBNET_ID、AGS_SECURITY_GROUP_ID、OTLP_ENDPOINT、SERVICE_NAME、
# BUSINESS_COMMAND，以及 EXTRA_ENV_JSON 中的业务环境变量。
set -a
source .env.local
set +a

DRY_RUN=true scripts/create_ags_tool.sh > ags-tool.generated.json
jq . ags-tool.generated.json
```

实例进入 `RUNNING` 后，注入本次运行身份：

```bash
export TENCENTCLOUD_SECRET_ID=<secret-id>
export TENCENTCLOUD_SECRET_KEY=<secret-key>
export TENCENTCLOUD_REGION=<region>
INSTANCE_ID=<ags-instance-id> scripts/inject_sandbox_id.sh
```

注入脚本应在客户控制面或交付流水线中运行，默认使用 AGS Go SDK command API。只有确认当前环境中的 `agr instance exec` 路径可用时，才设置 `INJECT_METHOD=agr`。

请使用 `scripts/create_ags_tool.sh` 生成正式提交给 AGS 的请求。不要直接提交 `iac/ags-tool.template.json`；它只是用于人工评审请求结构的模板。脚本会自动省略空 `RoleArn` 和空标签字段。

